module Documents
  class FailureStateService
    def self.call(document_id:, run_id:, error:)
      new(
        document_id: document_id,
        run_id: run_id,
        error: error
      ).call
    end

    def initialize(document_id:, run_id:, error:)
      @document_id = document_id
      @run_id = run_id
      @error = error
    end

    def call
      document = Document.find_by(id: document_id)

      return unless document

      document.with_lock do
        document.reload

        return unless current_run?(document)

        document.update!(
          status: "failed",
          metadata: (document.metadata || {}).merge(
            "ingestion_error_class" => error.class.name,
            "ingestion_error" => error.message,
            "ingestion_failed_at" => Time.current.iso8601
          )
        )
      end

      log_failure(document)
    rescue StandardError => state_error
      Rails.logger.error(
        event: "document_failure_state_update_failed",
        document_id: document_id,
        run_id: run_id,
        original_error_class: error.class.name,
        original_error_message: error.message,
        state_error_class: state_error.class.name,
        state_error_message: state_error.message
      )
    end

    private

    attr_reader :document_id, :run_id, :error

    def current_run?(document)
      document
        .metadata
        .to_h["ingestion_run_id"] == run_id
    end

    def log_failure(document)
      Rails.logger.error(
        event: "document_ingestion_failed",
        document_id: document.id,
        run_id: run_id,
        error_class: error.class.name,
        error_message: error.message
      )
    end
  end
end
