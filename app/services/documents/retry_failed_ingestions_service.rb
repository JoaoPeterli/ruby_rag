# frozen_string_literal: true

module Documents
  # O IngestionJob já tenta de novo sozinho pra falhas transitórias
  # (rate limit, timeout) com backoff — isso aqui é para depois que as
  # tentativas automáticas se esgotaram e o documento ficou parado em
  # status "failed" (nossa "dead letter queue" de fato, já que ela é o
  # Document, não uma fila separada).
  class RetryFailedIngestionsService
    class Error < StandardError; end

    def self.call(...)
      new(...).call
    end

    def initialize(
      scope: Document.where(status: "failed"),
      enqueue_service: Documents::EnqueueIngestionService,
      logger: Rails.logger
    )
      @scope = scope
      @enqueue_service = enqueue_service
      @logger = logger
    end

    def call
      scope.find_each.filter_map do |document|
        retry_document(document)
      end
    end

    private

    attr_reader :scope, :enqueue_service, :logger

    def retry_document(document)
      job = enqueue_service.call(document: document, force: true)

      logger.info(
        event: "document_ingestion_retry_enqueued",
        document_id: document.id,
        active_job_id: job&.job_id
      )

      { document_id: document.id, job_id: job&.job_id }
    rescue Documents::EnqueueIngestionService::Error => error
      logger.warn(
        event: "document_ingestion_retry_failed",
        document_id: document.id,
        error_class: error.class.name,
        error_message: error.message
      )

      nil
    end
  end
end
