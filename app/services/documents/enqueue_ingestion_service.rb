module Documents
  class EnqueueIngestionService
    class Error < StandardError; end
    class InvalidDocumentError < Error; end
    class EmptyContentError < Error; end
    class AlreadyScheduledError < Error; end

    def self.call(document:, force: false)
      new(document: document, force: force).call
    end

    def initialize(document:, force: false)
      @document = document
      @force = force
      @run_id = SecureRandom.uuid
    end

    def call
      validate_document!

      if skip_ingestion?
        log_skipped

        return nil
      end

      prepare_document!

      job = enqueue_job!

      save_job_information!(job)
      log_enqueued(job)

      job
    rescue Error
      raise
    rescue StandardError => error
      mark_enqueue_failure(error)

      raise Error,
            "Não foi possível enfileirar o documento: #{error.message}"
    end

    private

    attr_reader :document, :force, :run_id

    def skip_ingestion?
      !force && document.already_ingested_and_unchanged?
    end

    def log_skipped
      Rails.logger.info(
        event: "document_ingestion_skipped_unchanged",
        document_id: document.id,
        content_hash: document.content_hash,
        content_version: document.content_version
      )
    end

    def validate_document!
      unless document.is_a?(Document) && document.persisted?
        raise InvalidDocumentError,
              "O documento precisa estar persistido."
      end

      if document.content.to_s.strip.empty?
        raise EmptyContentError,
              "O documento não possui conteúdo para processamento."
      end
    end

    def prepare_document!
      document.with_lock do
        document.reload

        if document.status.in?(%w[queued processing])
          raise AlreadyScheduledError,
                "O documento já está na fila ou em processamento."
        end

        document.update!(
          status: "queued",
          metadata: cleaned_metadata.merge(
            "ingestion_run_id" => run_id,
            "ingestion_queued_at" => Time.current.iso8601,
            "ingestion_attempts" => 0
          )
        )
      end
    end

    def enqueue_job!
      Documents::IngestionJob.perform_later(
        document.id,
        run_id
      )
    end

    def save_job_information!(job)
      document.with_lock do
        document.reload

        return unless current_run_id == run_id

        document.update!(
          metadata: current_metadata.merge(
            "active_job_id" => job.job_id
          )
        )
      end
    end

    def mark_enqueue_failure(error)
      return unless document&.persisted?

      document.with_lock do
        document.reload

        return unless current_run_id == run_id

        document.update!(
          status: "failed",
          metadata: current_metadata.merge(
            "ingestion_error_class" => error.class.name,
            "ingestion_error" => error.message,
            "ingestion_failed_at" => Time.current.iso8601
          )
        )
      end
    rescue StandardError => update_error
      Rails.logger.error(
        event: "document_enqueue_failure_update_failed",
        document_id: document&.id,
        error_class: update_error.class.name,
        error_message: update_error.message
      )
    end

    def log_enqueued(job)
      Rails.logger.info(
        event: "document_ingestion_enqueued",
        document_id: document.id,
        run_id: run_id,
        active_job_id: job.job_id
      )
    end

    def current_run_id
      current_metadata["ingestion_run_id"]
    end

    def cleaned_metadata
      current_metadata.except(
        "ingestion_error",
        "ingestion_error_class",
        "ingestion_failed_at",
        "ingestion_completed_at",
        "processing_started_at",
        "worker_hostname",
        "worker_pid"
      )
    end

    def current_metadata
      document.metadata || {}
    end
  end
end
