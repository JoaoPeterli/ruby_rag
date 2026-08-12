# frozen_string_literal: true

module Documents
  class SemanticCacheLookupService
    DEFAULT_MINIMUM_SIMILARITY = 0.96

    Result = Data.define(:entry, :similarity)

    class Error < StandardError; end
    class InvalidEmbeddingError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(
      question_embedding:,
      minimum_similarity: DEFAULT_MINIMUM_SIMILARITY,
      scope: RagSemanticCacheEntry.not_expired,
      vector_store: Ai::VectorStoreService.default
    )
      @question_embedding = question_embedding
      @minimum_similarity = minimum_similarity
      @scope = scope
      @vector_store = vector_store
    end

    def call
      validate!

      point = nearest_point

      return unless point

      similarity = point.score.to_f.clamp(0.0, 1.0)

      return if similarity < minimum_similarity

      candidate = scope.find_by(id: point.id)

      return unless candidate

      register_hit(candidate)

      Result.new(entry: candidate, similarity: similarity)
    rescue Error
      raise
    rescue StandardError => error
      raise Error, "Falha ao consultar o cache semântico: #{error.message}"
    end

    private

    attr_reader :question_embedding, :minimum_similarity, :scope, :vector_store

    def validate!
      valid =
        question_embedding.is_a?(Array) &&
        question_embedding.any? &&
        question_embedding.all? { |value| value.is_a?(Numeric) }

      return if valid

      raise InvalidEmbeddingError,
            "question_embedding deve ser uma lista de números não vazia"
    end

    def nearest_point
      ids = scope.pluck(:id)

      return nil if ids.empty?

      vector_store.search(
        collection: Ai::Configuration::QDRANT_SEMANTIC_CACHE_COLLECTION,
        vector: question_embedding,
        limit: 1,
        ids: ids
      ).first
    end

    def register_hit(entry)
      entry.update!(
        hits: entry.hits + 1,
        last_hit_at: Time.current
      )
    end
  end
end
