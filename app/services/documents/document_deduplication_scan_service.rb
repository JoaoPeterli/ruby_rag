# frozen_string_literal: true

module Documents
  # Roda a deduplicação semântica em todos os chunks de um documento,
  # pensado pra ser disparado manualmente (console, rake, painel admin)
  # depois da ingestão — não faz parte do caminho crítico de ingestão.
  class DocumentDeduplicationScanService
    class Error < StandardError; end
    class InvalidDocumentError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(
      document:,
      deduplication_service: Documents::SemanticDeduplicationService,
      minimum_similarity:
        Documents::SemanticDeduplicationService::DEFAULT_MINIMUM_SIMILARITY
    )
      @document = document
      @deduplication_service = deduplication_service
      @minimum_similarity = minimum_similarity
    end

    def call
      validate!

      document.document_chunks.find_each.filter_map do |chunk|
        result = deduplication_service.call(
          chunk: chunk,
          minimum_similarity: minimum_similarity
        )

        next if result.duplicates.empty?

        result
      end
    rescue Documents::SemanticDeduplicationService::Error => error
      raise Error, "Falha ao escanear duplicatas do documento: #{error.message}"
    end

    private

    attr_reader :document, :deduplication_service, :minimum_similarity

    def validate!
      return if document.is_a?(Document) && document.persisted?

      raise InvalidDocumentError, "document deve ser um Document persistido"
    end
  end
end
