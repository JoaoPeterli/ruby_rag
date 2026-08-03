# frozen_string_literal: true

module Documents
  class MultiQueryService
    DEFAULT_MODEL = Ai::Configuration.chat_model
    DEFAULT_TEMPERATURE = 0.2
    DEFAULT_QUERY_COUNT = 4
    MAX_QUERY_COUNT = 8

    Result = Data.define(
      :original_question,
      :queries,
      :model,
      :usage,
      :duration_ms
    )

    class Error < StandardError; end
    class InvalidQuestionError < Error; end
    class InvalidQueryCountError < Error; end
    class GenerationError < Error; end
    class InvalidResponseError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(
      question:,
      query_count: DEFAULT_QUERY_COUNT,
      model: DEFAULT_MODEL,
      chat_completion_service: Ai::ChatCompletionService
    )
      @question = question
      @query_count = query_count
      @model = model
      @chat_completion_service = chat_completion_service
    end

    def call
      started_at = monotonic_time

      validate!

      chat_result = generate_queries
      generated_queries = parse_queries(chat_result)

      queries = build_queries(generated_queries)

      validate_queries!(queries)

      Result.new(
        original_question: normalized_question,
        queries: queries,
        model: chat_result.model || model,
        usage: chat_result.usage,
        duration_ms: elapsed_ms(started_at)
      )
    rescue Error
      raise
    rescue Ai::ChatCompletionService::Error => error
      raise GenerationError,
            "Não foi possível gerar múltiplas consultas: #{error.message}"
    rescue StandardError => error
      raise Error,
            "Falha inesperada ao gerar consultas: #{error.message}"
    end

    private

    attr_reader(
      :question,
      :query_count,
      :model,
      :chat_completion_service
    )

    def validate!
      validate_question!
      validate_query_count!
    end

    def validate_question!
      return if question.is_a?(String) && question.strip.present?

      raise InvalidQuestionError,
            "A pergunta deve ser uma string não vazia"
    end

    def validate_query_count!
      valid =
        query_count.is_a?(Integer) &&
        query_count.between?(1, MAX_QUERY_COUNT)

      return if valid

      raise InvalidQueryCountError,
            "query_count deve estar entre 1 e #{MAX_QUERY_COUNT}"
    end

    def normalized_question
      @normalized_question ||= question.strip
    end

    def generate_queries
      chat_completion_service.call(
        model: model,
        temperature: DEFAULT_TEMPERATURE,
        messages: [
          {
            role: "system",
            content: system_prompt
          },
          {
            role: "user",
            content: normalized_question
          }
        ]
      )
    end

    def system_prompt
      <<~PROMPT
        Você gera consultas alternativas para busca em um sistema RAG.

        Gere exatamente #{query_count} consultas diferentes que representem
        possíveis interpretações da pergunta do usuário.

        Regras:
        - Preserve a intenção original.
        - Não responda à pergunta.
        - Não invente fatos.
        - Use termos técnicos e sinônimos úteis.
        - Cada consulta deve explorar um aspecto diferente.
        - Cada consulta deve ter no máximo 35 palavras.
        - Retorne somente uma consulta por linha.
        - Não use numeração.
        - Não use marcadores.
        - Escreva em português.
      PROMPT
    end

    def parse_queries(chat_result)
      chat_result.content.to_s
        .lines
        .map(&:strip)
        .reject(&:blank?)
        .map { |query| remove_list_prefix(query) }
        .reject(&:blank?)
    end

    def remove_list_prefix(query)
      query.sub(/\A(?:[-*•]|\d+[.)])\s*/, "").strip
    end

    def build_queries(generated_queries)
      queries = [
        normalized_question,
        *generated_queries
      ]

      queries
        .map(&:strip)
        .reject(&:blank?)
        .uniq { |query| normalize_for_comparison(query) }
        .first(query_count + 1)
    end

    def normalize_for_comparison(value)
      value
        .unicode_normalize(:nfkd)
        .encode(
          "ASCII",
          invalid: :replace,
          undef: :replace,
          replace: ""
        )
        .downcase
        .gsub(/[^\p{Alnum}\s]/, " ")
        .squeeze(" ")
        .strip
    end

    def validate_queries!(queries)
      return if queries.size >= 2

      raise InvalidResponseError,
            "Não foram geradas consultas alternativas suficientes"
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_ms(started_at)
      ((monotonic_time - started_at) * 1_000).round(2)
    end
  end
end
