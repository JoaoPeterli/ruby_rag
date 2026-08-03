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
      scope: RagSemanticCacheEntry.not_expired
    )
      @question_embedding = question_embedding
      @minimum_similarity = minimum_similarity
      @scope = scope
    end

    def call
      validate!

      candidate = nearest_entry

      return unless candidate

      similarity = calculate_similarity(candidate)

      return if similarity < minimum_similarity

      register_hit(candidate)

      Result.new(entry: candidate, similarity: similarity)
    rescue Error
      raise
    rescue StandardError => error
      raise Error, "Falha ao consultar o cache semântico: #{error.message}"
    end

    private

    attr_reader :question_embedding, :minimum_similarity, :scope

    def validate!
      valid =
        question_embedding.is_a?(Array) &&
        question_embedding.any? &&
        question_embedding.all? { |value| value.is_a?(Numeric) }

      return if valid

      raise InvalidEmbeddingError,
            "question_embedding deve ser uma lista de números não vazia"
    end

    def nearest_entry
      scope
        .nearest_neighbors(
          :question_embedding,
          question_embedding,
          distance: "cosine"
        )
        .first
    end

    def calculate_similarity(entry)
      distance = entry.neighbor_distance.to_f

      (1.0 - distance).clamp(0.0, 1.0)
    end

    def register_hit(entry)
      entry.update!(
        hits: entry.hits + 1,
        last_hit_at: Time.current
      )
    end
  end
end
