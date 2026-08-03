module Documents
  class ProcessingGuard
    class Error < StandardError; end
    class InvalidDocumentError < Error; end
    class StaleRunError < Error; end
    class InvalidStatusError < Error; end

    def self.call(document:, run_id:)
      new(
        document: document,
        run_id: run_id
      ).call
    end

    def initialize(document:, run_id:)
      @document = document
      @run_id = run_id
    end

    def call
      validate_document!

      document.with_lock do
        document.reload

        validate_current_run!
        validate_status!

        register_processing_attempt!
      end

      document
    end

    private

    attr_reader :document, :run_id

    def validate_document!
      unless document.is_a?(Document) && document.persisted?
        raise InvalidDocumentError,
              "O documento precisa estar persistido."
      end

      if run_id.to_s.strip.empty?
        raise StaleRunError,
              "O identificador da execução não foi informado."
      end
    end

    def validate_current_run!
      return if current_run_id == run_id

      raise StaleRunError,
            "Este Job pertence a uma execução antiga do documento."
    end

    def validate_status!
      return if document.status.in?(%w[queued processing])

      raise InvalidStatusError,
            "O documento está com status inválido para processamento: " \
            "#{document.status}."
    end

    def register_processing_attempt!
      attempt = current_attempt + 1

      document.update!(
        status: "processing",
        metadata: current_metadata.merge(
          "processing_started_at" => Time.current.iso8601,
          "processing_last_attempt_at" => Time.current.iso8601,
          "ingestion_attempts" => attempt,
          "worker_hostname" => Socket.gethostname,
          "worker_pid" => Process.pid
        )
      )

      log_started(attempt)
    end

    def current_attempt
      current_metadata
        .fetch("ingestion_attempts", 0)
        .to_i
    end

    def current_run_id
      current_metadata["ingestion_run_id"]
    end

    def current_metadata
      document.metadata || {}
    end

    def log_started(attempt)
      Rails.logger.info(
        event: "document_ingestion_started",
        document_id: document.id,
        run_id: run_id,
        attempt: attempt,
        worker_hostname: Socket.gethostname,
        worker_pid: Process.pid
      )
    end
  end
end
