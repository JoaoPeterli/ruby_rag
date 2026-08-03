# frozen_string_literal: true

module Documents
  class VectorSearchService
    DEFAULT_LIMIT = 5
    DEFAULT_CANDIDATE_LIMIT = 20
    DEFAULT_MINIMUM_SIMILARITY = 0.55

    Result = Data.define(
      :chunk,
      :distance,
      :similarity,
      :position
    )

    class Error < StandardError; end
    class InvalidQueryError < Error; end
    class InvalidEmbeddingError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(
      query:,
      query_embedding:,
      limit: DEFAULT_LIMIT,
      candidate_limit: DEFAULT_CANDIDATE_LIMIT,
      minimum_similarity: DEFAULT_MINIMUM_SIMILARITY,
      relation: DocumentChunk.all,
      filters: Documents::MetadataFilters.empty,
      scope_builder: Documents::MetadataScopeBuilder
    )
      @query = query
      @query_embedding = query_embedding
      @limit = limit
      @candidate_limit = candidate_limit
      @minimum_similarity = minimum_similarity
      @relation = relation
      @filters = filters
      @scope_builder = scope_builder
    end

    def call
      validate!

      candidates = search_candidates

      candidates
        .filter_map
        .with_index(1) do |chunk, position|
          build_result(chunk, position)
        end
        .first(limit)
    end

    private

    attr_reader(
      :query,
      :query_embedding,
      :limit,
      :candidate_limit,
      :minimum_similarity,
      :relation,
      :filters,
      :scope_builder
    )

    def search_candidates
      filtered_scope
        .nearest_neighbors(
          :embedding,
          query_embedding,
          distance: "cosine"
        )
        .first(candidate_limit)
    end

    def filtered_scope
      scope_builder.call(
        scope: relation,
        filters: filters
      )
    end

    def build_result(chunk, position)
      distance = extract_distance(chunk)
      similarity = calculate_similarity(distance)

      return if similarity < minimum_similarity

      Result.new(
        chunk: chunk,
        distance: distance,
        similarity: similarity,
        position: position
      )
    end

    def extract_distance(chunk)
      distance = chunk.neighbor_distance

      unless distance.is_a?(Numeric)
        raise Error, "A distância vetorial retornada é inválida"
      end

      distance.to_f
    end

    def calculate_similarity(distance)
      similarity = 1.0 - distance

      similarity.clamp(0.0, 1.0)
    end

    def validate!
      validate_query!
      validate_embedding!
      validate_limit!
      validate_candidate_limit!
      validate_minimum_similarity!
    end

    def validate_query!
      return if query.is_a?(String) && query.present?

      raise InvalidQueryError,
            "A pergunta deve ser uma string não vazia"
    end

    def validate_embedding!
      valid = query_embedding.is_a?(Array) &&
              query_embedding.present? &&
              query_embedding.all? { |value| value.is_a?(Numeric) }

      return if valid

      raise InvalidEmbeddingError,
            "O embedding da pergunta deve ser uma lista de números"
    end

    def validate_limit!
      return if limit.is_a?(Integer) && limit.positive?

      raise ArgumentError,
            "limit deve ser um número inteiro maior que zero"
    end

    def validate_candidate_limit!
      valid = candidate_limit.is_a?(Integer) &&
              candidate_limit.positive? &&
              candidate_limit >= limit

      return if valid

      raise ArgumentError,
            "candidate_limit deve ser maior ou igual a limit"
    end

    def validate_minimum_similarity!
      valid = minimum_similarity.is_a?(Numeric) &&
              minimum_similarity.between?(0.0, 1.0)

      return if valid

      raise ArgumentError,
            "minimum_similarity deve estar entre 0 e 1"
    end
  end
end
