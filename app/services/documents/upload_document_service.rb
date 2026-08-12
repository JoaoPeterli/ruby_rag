# frozen_string_literal: true

module Documents
  # Entrada do fluxo de upload (Portal::DocumentsController#create,
  # atrás de DOCUMENT_UPLOAD_ENABLED). Cria o Document já em
  # status: "uploaded" (sem content ainda), anexa o arquivo enviado e
  # enfileira Documents::OcrExtractionJob -- espelha o formato de
  # Documents::EnqueueIngestionService (valida, persiste, enfileira,
  # marca falha em caso de erro).
  class UploadDocumentService
    class Error < StandardError; end
    class InvalidAccountError < Error; end
    class InvalidTitleError < Error; end
    class MissingFileError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(
      account:,
      title:,
      file:,
      ramo: nil,
      seguradora: nil,
      cliente: nil,
      tipo_documento: nil,
      vigencia_ano: nil
    )
      @account = account
      @title = title
      @file = file
      @ramo = ramo
      @seguradora = seguradora
      @cliente = cliente
      @tipo_documento = tipo_documento
      @vigencia_ano = vigencia_ano
      @run_id = SecureRandom.uuid
    end

    def call
      validate!

      @document = create_document!
      job = enqueue_job!(document)

      save_job_information!(job)
      log_enqueued(job)

      document
    rescue Error
      raise
    rescue StandardError => error
      mark_upload_failure(error)

      raise Error, "Não foi possível enviar o documento: #{error.message}"
    end

    private

    attr_reader :account, :title, :file, :ramo, :seguradora, :cliente,
                :tipo_documento, :vigencia_ano, :run_id, :document

    def validate!
      unless account.is_a?(Account) && account.persisted?
        raise InvalidAccountError, "A conta precisa estar persistida."
      end

      raise InvalidTitleError, "O título é obrigatório." if title.to_s.strip.blank?
      raise MissingFileError, "Nenhum arquivo foi enviado." if file.blank?
    end

    def create_document!
      document = account.documents.create!(
        title: title,
        status: "uploaded",
        ramo: ramo,
        seguradora: seguradora,
        cliente: cliente,
        tipo_documento: tipo_documento,
        vigencia_ano: vigencia_ano,
        metadata: {
          "ocr_run_id" => run_id,
          "ocr_queued_at" => Time.current.iso8601
        }
      )

      document.source_file.attach(file)

      document
    end

    def enqueue_job!(document)
      Documents::OcrExtractionJob.perform_later(document.id, run_id)
    end

    def save_job_information!(job)
      document.with_lock do
        document.reload

        return unless current_run_id == run_id

        document.update!(metadata: document.metadata.merge("active_job_id" => job.job_id))
      end
    end

    def mark_upload_failure(error)
      Rails.logger.error(
        event: "document_upload_failed",
        document_id: document&.id,
        error_class: error.class.name,
        error_message: error.message
      )

      return unless document&.persisted?

      document.with_lock do
        document.reload

        return unless current_run_id == run_id

        document.update!(
          status: "failed",
          metadata: document.metadata.merge(
            "ocr_error_class" => error.class.name,
            "ocr_error" => error.message,
            "ocr_failed_at" => Time.current.iso8601
          )
        )
      end
    rescue StandardError => update_error
      Rails.logger.error(
        event: "document_upload_failure_update_failed",
        document_id: document&.id,
        error_class: update_error.class.name,
        error_message: update_error.message
      )
    end

    def log_enqueued(job)
      Rails.logger.info(
        event: "document_upload_enqueued",
        document_id: document.id,
        run_id: run_id,
        active_job_id: job.job_id
      )
    end

    def current_run_id
      document.metadata.to_h["ocr_run_id"]
    end
  end
end
