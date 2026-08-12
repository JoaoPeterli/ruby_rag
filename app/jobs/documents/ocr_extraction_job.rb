module Documents
  class OcrExtractionJob < ApplicationJob
    queue_as :document_ocr

    class StaleRunError < StandardError; end

    # Falhas desconhecidas recebem poucas tentativas.
    retry_on(
      StandardError,
      wait: :polynomially_longer,
      attempts: 3
    ) do |job, error|
      job.handle_final_failure(error)
    end

    # Não adianta repetir um tipo de arquivo que nunca vai funcionar.
    discard_on(
      Documents::OcrService::UnsupportedFileError
    ) do |job, error|
      job.handle_final_failure(error)
    end

    # Um Job antigo não pode alterar uma execução nova (ex.: usuário
    # reenviou o arquivo antes do primeiro OCR terminar).
    discard_on(StaleRunError) do |job, error|
      job.log_stale_job(error)
    end

    discard_on ActiveJob::DeserializationError

    def perform(document_id, run_id)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      document = Document.find(document_id)

      guard_current_run!(document, run_id)

      result = Documents::OcrService.call(file: document.source_file)

      document.update!(
        content: result.text,
        status: "pending",
        metadata: document.metadata.merge(
          "ocr_engine" => result.engine,
          "ocr_duration_ms" => result.duration_ms,
          "ocr_completed_at" => Time.current.iso8601
        )
      )

      Rails.logger.info(
        event: "document_ocr_job_completed",
        document_id: document.id,
        run_id: run_id,
        engine: result.engine,
        duration_ms: elapsed_milliseconds(started_at)
      )

      Documents::EnqueueIngestionService.call(document: document)
    end

    def handle_final_failure(error)
      document_id, run_id = arguments

      document = Document.find_by(id: document_id)

      return unless document

      document.with_lock do
        document.reload

        return unless document.metadata.to_h["ocr_run_id"] == run_id

        document.update!(
          status: "failed",
          metadata: document.metadata.merge(
            "ocr_error_class" => error.class.name,
            "ocr_error" => error.message,
            "ocr_failed_at" => Time.current.iso8601
          )
        )
      end

      Rails.logger.error(
        event: "document_ocr_failed",
        document_id: document_id,
        run_id: run_id,
        error_class: error.class.name,
        error_message: error.message
      )
    end

    def log_stale_job(error)
      document_id, run_id = arguments

      Rails.logger.warn(
        event: "stale_document_ocr_job_discarded",
        document_id: document_id,
        run_id: run_id,
        error_class: error.class.name,
        error_message: error.message
      )
    end

    private

    def guard_current_run!(document, run_id)
      return if document.metadata.to_h["ocr_run_id"] == run_id

      raise StaleRunError, "Este Job pertence a uma execução antiga do documento."
    end

    def elapsed_milliseconds(started_at)
      finished_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      ((finished_at - started_at) * 1_000).round
    end
  end
end
