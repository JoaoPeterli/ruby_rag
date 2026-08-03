# frozen_string_literal: true

module Documents
  class MultiQueryResultMerger
    DEFAULT_LIMIT = 40

    Result = Data.define(
      :chunk,
      :distance,
      :similarity,
      :vector_position,
      :text_position,
      :text_score,
      :normalized_text_score,
      :hybrid_score,
      :position,
      :matched_queries,
      :query_match_count,
      :best_query_position,
      :multi_query_score
    )

    class Error < StandardError; end
    class InvalidResultsError < Error; end
    class InvalidLimitError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(
      query_results:,
      limit: DEFAULT_LIMIT
    )
      @query_results = query_results
      @limit = limit
    end

    def call
      validate!

      merged_results = grouped_results.map do |_chunk_id, entries|
        build_result(entries)
      end

      merged_results
        .sort_by { |result| -result.multi_query_score }
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

    attr_reader :query_results, :limit

    def validate!
      validate_results!
      validate_limit!
    end

    def validate_results!
      valid =
        query_results.is_a?(Array) &&
        query_results.all? do |entry|
          entry.is_a?(Hash) &&
            entry[:query].is_a?(String) &&
            entry[:query_position].is_a?(Integer) &&
            entry[:results].is_a?(Array)
        end

      return if valid

      raise InvalidResultsError,
            "Os resultados das consultas são inválidos"
    end

    def validate_limit!
      return if limit.is_a?(Integer) && limit.positive?

      raise InvalidLimitError,
            "limit deve ser um inteiro maior que zero"
    end

    def grouped_results
      query_results
        .flat_map do |entry|
          entry.fetch(:results).map do |result|
            {
              query: entry.fetch(:query),
              query_position: entry.fetch(:query_position),
              result: result
            }
          end
        end
        .group_by do |entry|
          entry.fetch(:result).chunk.id
        end
    end

    def build_result(entries)
      best_entry = entries.max_by do |entry|
        entry.fetch(:result).hybrid_score.to_f
      end

      best_result = best_entry.fetch(:result)

      matched_queries =
        entries
          .map { |entry| entry.fetch(:query) }
          .uniq

      query_match_count = matched_queries.size

      multi_query_score = calculate_multi_query_score(
        best_hybrid_score: best_result.hybrid_score.to_f,
        query_match_count: query_match_count
      )

      Result.new(
        chunk: best_result.chunk,
        distance: best_result.distance,
        similarity: best_result.similarity,
        vector_position: best_result.vector_position,
        text_position: best_result.text_position,
        text_score: best_result.text_score,
        normalized_text_score: best_result.normalized_text_score,
        hybrid_score: best_result.hybrid_score,
        position: nil,
        matched_queries: matched_queries,
        query_match_count: query_match_count,
        best_query_position: best_entry.fetch(:query_position),
        multi_query_score: multi_query_score
      )
    end

    def calculate_multi_query_score(
      best_hybrid_score:,
      query_match_count:
    )
      frequency_bonus =
        [ query_match_count - 1, 3 ].min * 0.05

      (
        best_hybrid_score +
        frequency_bonus
      ).clamp(0.0, 1.0).round(6)
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
        position: position,
        matched_queries: result.matched_queries,
        query_match_count: result.query_match_count,
        best_query_position: result.best_query_position,
        multi_query_score: result.multi_query_score
      )
    end
  end
end
