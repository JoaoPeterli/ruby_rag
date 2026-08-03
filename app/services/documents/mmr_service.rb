# frozen_string_literal: true

module Documents
  class MmrService
    DEFAULT_LIMIT = 5
    DEFAULT_LAMBDA = 0.70

    Result = Data.define(
      :chunk,
      :distance,
      :similarity,
      :position,
      :original_position,
      :vector_position,
      :text_position,
      :text_score,
      :normalized_text_score,
      :hybrid_score,
      :multi_query_score,
      :matched_queries,
      :query_match_count,
      :best_query_position,
      :vector_score,
      :lexical_score,
      :position_score,
      :rerank_score,
      :matched_terms,
      :cross_encoder_score,
      :cross_encoder_reason,
      :combined_score,
      :mmr_score,
      :redundancy_score
    )

    class Error < StandardError; end
    class InvalidResultsError < Error; end
    class InvalidLimitError < Error; end
    class InvalidLambdaError < Error; end
    class MissingEmbeddingError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(
      results:,
      limit: DEFAULT_LIMIT,
      lambda_value: DEFAULT_LAMBDA
    )
      @results = results
      @limit = limit
      @lambda_value = lambda_value
    end

    def call
      validate!

      selected = []
      remaining = results.dup

      while selected.size < limit && remaining.any?
        candidate = select_best_candidate(
          remaining: remaining,
          selected: selected
        )

        selected << candidate
        remaining.delete(candidate.fetch(:result))
      end

      selected.each_with_index.map do |candidate, index|
        build_result(
          candidate: candidate,
          position: index + 1
        )
      end
    end

    private

    attr_reader :results, :limit, :lambda_value

    def validate!
      validate_results!
      validate_limit!
      validate_lambda!
      validate_embeddings!
    end

    def validate_results!
      valid =
        results.is_a?(Array) &&
        results.all? do |result|
          result.respond_to?(:chunk) &&
            (
              result.respond_to?(:combined_score) ||
              result.respond_to?(:rerank_score) ||
              result.respond_to?(:similarity)
            )
        end

      return if valid

      raise InvalidResultsError,
            "Os resultados enviados para o MMR são inválidos"
    end

    def validate_limit!
      return if limit.is_a?(Integer) && limit.positive?

      raise InvalidLimitError,
            "limit deve ser um número inteiro maior que zero"
    end

    def validate_lambda!
      valid =
        lambda_value.is_a?(Numeric) &&
        lambda_value.between?(0.0, 1.0)

      return if valid

      raise InvalidLambdaError,
            "lambda_value deve estar entre 0 e 1"
    end

    def validate_embeddings!
      invalid_result = results.find do |result|
        embedding = extract_embedding(result.chunk)

        !valid_embedding?(embedding)
      end

      return unless invalid_result

      raise MissingEmbeddingError,
            "O chunk #{invalid_result.chunk.id} não possui embedding válido"
    end

    def select_best_candidate(remaining:, selected:)
      remaining
        .map do |result|
          build_candidate(
            result: result,
            selected: selected
          )
        end
        .max_by { |candidate| candidate.fetch(:mmr_score) }
    end

    def build_candidate(result:, selected:)
      redundancy_score = calculate_redundancy(
        result: result,
        selected: selected
      )

      relevance_score = normalize_score(
        relevance_score_for(result)
      )

      mmr_score =
        (lambda_value * relevance_score) -
        ((1.0 - lambda_value) * redundancy_score)

      {
        result: result,
        relevance_score: relevance_score,
        redundancy_score: redundancy_score,
        mmr_score: mmr_score.round(6)
      }
    end

    def calculate_redundancy(result:, selected:)
      return 0.0 if selected.empty?

      candidate_embedding = extract_embedding(result.chunk)

      selected
        .map do |selected_candidate|
          selected_result = selected_candidate.fetch(:result)

          cosine_similarity(
            candidate_embedding,
            extract_embedding(selected_result.chunk)
          )
        end
        .max
        .to_f
    end

    def cosine_similarity(vector_a, vector_b)
      return 0.0 unless vector_a.size == vector_b.size

      dot_product = 0.0
      norm_a = 0.0
      norm_b = 0.0

      vector_a.each_index do |index|
        value_a = vector_a[index].to_f
        value_b = vector_b[index].to_f

        dot_product += value_a * value_b
        norm_a += value_a * value_a
        norm_b += value_b * value_b
      end

      denominator = Math.sqrt(norm_a) * Math.sqrt(norm_b)

      return 0.0 if denominator.zero?

      normalize_score(dot_product / denominator)
    end

    def build_result(candidate:, position:)
      result = candidate.fetch(:result)
      underlying = unwrap(result)

      Result.new(
        chunk: underlying.chunk,
        distance: underlying.distance,
        similarity: underlying.similarity,
        position: position,
        original_position: underlying.original_position,
        vector_position: underlying.vector_position,
        text_position: underlying.text_position,
        text_score: underlying.text_score,
        normalized_text_score: underlying.normalized_text_score,
        hybrid_score: underlying.hybrid_score,
        multi_query_score: underlying.multi_query_score,
        matched_queries: underlying.matched_queries,
        query_match_count: underlying.query_match_count,
        best_query_position: underlying.best_query_position,
        vector_score: underlying.vector_score,
        lexical_score: underlying.lexical_score,
        position_score: underlying.position_score,
        rerank_score: underlying.rerank_score,
        matched_terms: underlying.matched_terms,
        cross_encoder_score: extract_optional(result, :cross_encoder_score),
        cross_encoder_reason: extract_optional(result, :cross_encoder_reason),
        combined_score: extract_optional(result, :combined_score),
        mmr_score: candidate.fetch(:mmr_score),
        redundancy_score: candidate.fetch(:redundancy_score)
      )
    end

    def relevance_score_for(result)
      if result.respond_to?(:combined_score)
        result.combined_score.to_f
      elsif result.respond_to?(:rerank_score)
        result.rerank_score.to_f
      elsif result.respond_to?(:hybrid_score)
        result.hybrid_score.to_f
      else
        result.similarity.to_f
      end
    end

    def unwrap(result)
      result.respond_to?(:result) ? result.result : result
    end

    def extract_optional(result, attribute)
      return unless result.respond_to?(attribute)

      result.public_send(attribute)
    end

    def extract_embedding(chunk)
      embedding = chunk.embedding

      if embedding.respond_to?(:to_a)
        embedding.to_a
      else
        embedding
      end
    end

    def valid_embedding?(embedding)
      embedding.is_a?(Array) &&
        embedding.any? &&
        embedding.all? { |value| value.is_a?(Numeric) }
    end

    def normalize_score(value)
      value.to_f.clamp(0.0, 1.0)
    end
  end
end
