# frozen_string_literal: true

module Documents
  class HybridSearchService
    DEFAULT_LIMIT = 20

    VECTOR_WEIGHT = 0.70
    TEXT_WEIGHT = 0.30

    Result = Data.define(
      :chunk,
      :distance,
      :similarity,
      :vector_position,
      :text_position,
      :text_score,
      :normalized_text_score,
      :hybrid_score,
      :position
    )

    class Error < StandardError; end
    class InvalidVectorResultsError < Error; end
    class InvalidTextResultsError < Error; end
    class InvalidLimitError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(
      vector_results:,
      text_results:,
      limit: DEFAULT_LIMIT
    )
      @vector_results = vector_results
      @text_results = text_results
      @limit = limit
    end

    def call
      validate!

      maximum_text_score = calculate_maximum_text_score

      combined_results = result_chunks.map do |chunk|
        build_result(
          chunk: chunk,
          maximum_text_score: maximum_text_score
        )
      end

      combined_results
        .sort_by { |result| -result.hybrid_score }
        .first(limit)
        .each_with_index
        .map do |result, index|
          rebuild_with_position(
            result,
            position: index + 1
          )
        end
    end

    private

    attr_reader(
      :vector_results,
      :text_results,
      :limit
    )

    def validate!
      validate_vector_results!
      validate_text_results!
      validate_limit!
    end

    def validate_vector_results!
      valid =
        vector_results.is_a?(Array) &&
        vector_results.all? do |result|
          result.respond_to?(:chunk) &&
            result.respond_to?(:similarity) &&
            result.respond_to?(:distance) &&
            result.respond_to?(:position)
        end

      return if valid

      raise InvalidVectorResultsError,
            "Os resultados vetoriais são inválidos"
    end

    def validate_text_results!
      valid =
        text_results.is_a?(Array) &&
        text_results.all? do |result|
          result.respond_to?(:chunk) &&
            result.respond_to?(:text_score) &&
            result.respond_to?(:position)
        end

      return if valid

      raise InvalidTextResultsError,
            "Os resultados textuais são inválidos"
    end

    def validate_limit!
      return if limit.is_a?(Integer) && limit.positive?

      raise InvalidLimitError,
            "limit deve ser um número inteiro maior que zero"
    end

    def result_chunks
      (
        vector_results.map(&:chunk) +
        text_results.map(&:chunk)
      ).uniq(&:id)
    end

    def build_result(chunk:, maximum_text_score:)
      vector_result = find_vector_result(chunk)
      text_result = find_text_result(chunk)

      similarity = vector_result&.similarity.to_f
      text_score = text_result&.text_score.to_f

      normalized_text_score = normalize_text_score(
        text_score,
        maximum_text_score
      )

      hybrid_score =
        (similarity * VECTOR_WEIGHT) +
        (normalized_text_score * TEXT_WEIGHT)

      Result.new(
        chunk: chunk,
        distance: vector_result&.distance,
        similarity: similarity,
        vector_position: vector_result&.position,
        text_position: text_result&.position,
        text_score: text_score,
        normalized_text_score: normalized_text_score,
        hybrid_score: hybrid_score.round(6),
        position: nil
      )
    end

    def rebuild_with_position(result, position:)
      Result.new(
        chunk: result.chunk,
        distance: result.distance,
        similarity: result.similarity,
        vector_position: result.vector_position,
        text_position: result.text_position,
        text_score: result.text_score,
        normalized_text_score: result.normalized_text_score,
        hybrid_score: result.hybrid_score,
        position: position
      )
    end

    def find_vector_result(chunk)
      vector_results.find do |result|
        result.chunk.id == chunk.id
      end
    end

    def find_text_result(chunk)
      text_results.find do |result|
        result.chunk.id == chunk.id
      end
    end

    def calculate_maximum_text_score
      text_results
        .map { |result| result.text_score.to_f }
        .max
        .to_f
    end

    def normalize_text_score(score, maximum_score)
      return 0.0 if maximum_score.zero?

      (score / maximum_score).clamp(0.0, 1.0)
    end
  end
end
