# frozen_string_literal: true

module Documents
  # Documentos ficam em status "processing" enquanto um IngestionJob
  # está rodando (ver Documents::ProcessingGuard). Se o worker morrer no
  # meio do processamento (deploy, OOM kill, job perdido do Redis), o
  # documento fica preso em "processing" para sempre: EnqueueIngestionService
  # recusa reenfileirar (mesmo com force: true) qualquer documento nesse
  # status, e Documents::RetryFailedIngestionsService só enxerga "failed".
  #
  # Este serviço é a rede de segurança: transiciona para "failed" qualquer
  # documento em "processing" sem nenhuma tentativa registrada há mais de
  # stale_after, devolvendo-o para o fluxo de recuperação que já existe
  # (painel admin de falhas / RetryFailedIngestionsService).
  class ReconcileStaleProcessingDocumentsService
    DEFAULT_STALE_AFTER = 30.minutes

    ERROR_CLASS = "Documents::ReconcileStaleProcessingDocumentsService::StaleProcessingError"

    def self.call(...)
      new(...).call
    end

    def initialize(
      stale_after: DEFAULT_STALE_AFTER,
      scope: Document.where(status: "processing")
    )
      @stale_after = stale_after
      @scope = scope
    end

    def call
      scope.find_each.filter_map do |document|
        reconcile(document)
      end
    end

    private

    attr_reader :stale_after, :scope

    def reconcile(document)
      reconciled = false

      document.with_lock do
        document.reload

        next unless document.status == "processing"
        next unless stale?(document)

        document.update!(
          status: "failed",
          metadata: document.metadata.to_h.merge(
            "ingestion_error_class" => ERROR_CLASS,
            "ingestion_error" =>
              "Nenhuma tentativa de ingestão registrada nos últimos " \
              "#{stale_after.inspect} — o worker provavelmente foi " \
              "interrompido no meio do processamento.",
            "ingestion_failed_at" => Time.current.iso8601
          )
        )

        reconciled = true
      end

      { document_id: document.id } if reconciled
    end

    def stale?(document)
      last_attempt_at(document) < stale_after.ago
    end

    def last_attempt_at(document)
      metadata = document.metadata.to_h
      timestamp =
        metadata["processing_last_attempt_at"] ||
        metadata["processing_started_at"]

      return Time.at(0) if timestamp.blank?

      Time.iso8601(timestamp)
    rescue ArgumentError
      Time.at(0)
    end
  end
end
