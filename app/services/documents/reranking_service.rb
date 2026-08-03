# frozen_string_literal: true

module Documents
  class RerankingService
    DEFAULT_LIMIT = 5

    VECTOR_WEIGHT = 0.70
    LEXICAL_WEIGHT = 0.25
    POSITION_WEIGHT = 0.05

    STOP_WORDS = %w[
      a à ao aos as o os
      de da das do dos
      e em para por com
      um uma uns umas
      que qual quais
      como onde quando
      porque porquê
      é são foi foram
      ser estar está estão
      antes depois
    ].freeze

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
      :matched_terms
    )

    class Error < StandardError; end
    class InvalidQuestionError < Error; end
    class InvalidSearchResultsError < Error; end
    class InvalidLimitError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(
      question:,
      search_results:,
      limit: DEFAULT_LIMIT
    )
      @question = question
      @search_results = search_results
      @limit = limit
    end

    def call
      validate!

      question_terms = extract_terms(normalized_question)

      ranked_results =
        search_results.map do |search_result|
          build_result(
            search_result: search_result,
            question_terms: question_terms
          )
        end

      ranked_results
        .sort_by { |result| -result.rerank_score }
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
      :question,
      :search_results,
      :limit
    )

    def validate!
      validate_question!
      validate_search_results!
      validate_limit!
    end

    def validate_question!
      return if question.is_a?(String) && question.strip.present?

      raise InvalidQuestionError,
            "A pergunta deve ser uma string não vazia"
    end

    def validate_search_results!
      valid =
        search_results.is_a?(Array) &&
        search_results.all? do |result|
          result.respond_to?(:chunk) &&
            result.respond_to?(:similarity) &&
            result.respond_to?(:position)
        end

      return if valid

      raise InvalidSearchResultsError,
            "Os resultados da busca são inválidos"
    end

    def validate_limit!
      return if limit.is_a?(Integer) && limit.positive?

      raise InvalidLimitError,
            "limit deve ser um número inteiro maior que zero"
    end

    def build_result(search_result:, question_terms:)
      chunk_text = extract_chunk_text(search_result.chunk)

      chunk_terms = extract_terms(chunk_text)

      matched_terms = question_terms & chunk_terms

      relevance_score = extract_relevance_score(search_result)

      lexical_score = calculate_lexical_score(
        question_terms: question_terms,
        matched_terms: matched_terms
      )

      position_score = calculate_position_score(
        search_result.position
      )

      rerank_score = calculate_rerank_score(
        vector_score: relevance_score,
        lexical_score: lexical_score,
        position_score: position_score
      )

      Result.new(
        chunk: search_result.chunk,
        distance: extract_value(search_result, :distance),
        similarity: extract_value(search_result, :similarity).to_f,
        position: search_result.position,
        original_position: search_result.position,
        vector_position: extract_value(search_result, :vector_position),
        text_position: extract_value(search_result, :text_position),
        text_score: extract_value(search_result, :text_score).to_f,
        normalized_text_score:
          extract_value(search_result, :normalized_text_score).to_f,
        hybrid_score: extract_value(search_result, :hybrid_score).to_f,
        multi_query_score:
          extract_value(search_result, :multi_query_score).to_f,
        matched_queries:
          extract_value(search_result, :matched_queries) || [],
        query_match_count:
          extract_value(search_result, :query_match_count).to_i,
        best_query_position:
          extract_value(search_result, :best_query_position),
        vector_score: relevance_score,
        lexical_score: lexical_score,
        position_score: position_score,
        rerank_score: rerank_score,
        matched_terms: matched_terms
      )
    end

    def rebuild_with_position(result, position:)
      Result.new(
        chunk: result.chunk,
        distance: result.distance,
        similarity: result.similarity,
        position: position,
        original_position: result.original_position,
        vector_position: result.vector_position,
        text_position: result.text_position,
        text_score: result.text_score,
        normalized_text_score: result.normalized_text_score,
        hybrid_score: result.hybrid_score,
        multi_query_score: result.multi_query_score,
        matched_queries: result.matched_queries,
        query_match_count: result.query_match_count,
        best_query_position: result.best_query_position,
        vector_score: result.vector_score,
        lexical_score: result.lexical_score,
        position_score: result.position_score,
        rerank_score: result.rerank_score,
        matched_terms: result.matched_terms
      )
    end

    def extract_relevance_score(search_result)
      if search_result.respond_to?(:multi_query_score)
        normalize_score(search_result.multi_query_score)
      elsif search_result.respond_to?(:hybrid_score)
        normalize_score(search_result.hybrid_score)
      else
        normalize_score(search_result.similarity)
      end
    end

    def extract_value(result, attribute)
      return unless result.respond_to?(attribute)

      result.public_send(attribute)
    end

    def extract_chunk_text(chunk)
      content =
        if chunk.respond_to?(:content)
          chunk.content
        elsif chunk.respond_to?(:text)
          chunk.text
        end

      content.to_s
    end

    def calculate_lexical_score(question_terms:, matched_terms:)
      return 0.0 if question_terms.empty?

      matched_terms.size.to_f / question_terms.size
    end

    def calculate_position_score(position)
      normalized_position = position.to_i

      return 0.0 unless normalized_position.positive?

      1.0 / normalized_position
    end

    def calculate_rerank_score(
      vector_score:,
      lexical_score:,
      position_score:
    )
      score =
        (vector_score * VECTOR_WEIGHT) +
        (lexical_score * LEXICAL_WEIGHT) +
        (position_score * POSITION_WEIGHT)

      score.round(6)
    end

    def extract_terms(text)
      normalize_text(text)
        .scan(/[a-z0-9]+/)
        .reject { |term| term.length < 3 }
        .reject { |term| STOP_WORDS.include?(term) }
        .uniq
    end

    def normalize_text(text)
      I18n.transliterate(text.to_s)
          .downcase
          .gsub(/[^a-z0-9\s]/, " ")
          .squeeze(" ")
          .strip
    end

    def normalize_score(value)
      value.to_f.clamp(0.0, 1.0)
    end

    def normalized_question
      @normalized_question ||= question.strip
    end
  end
end
