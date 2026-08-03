# frozen_string_literal: true

module Documents
  class QueryExpansionService
    DEFAULT_MODEL = Ai::Configuration.chat_model
    DEFAULT_TEMPERATURE = 0.0

    Result = Data.define(
      :original_question,
      :expanded_query,
      :model,
      :usage,
      :duration_ms
    )

    class Error < StandardError; end
    class InvalidQuestionError < Error; end
    class GenerationError < Error; end
    class InvalidResponseError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(
      question:,
      model: DEFAULT_MODEL,
      chat_completion_service: Ai::ChatCompletionService
    )
      @question = question
      @model = model
      @chat_completion_service = chat_completion_service
    end

    def call
      started_at = monotonic_time

      validate!

      chat_result = generate_expansion
      expanded_query = extract_expanded_query(chat_result)

      validate_expanded_query!(expanded_query)

      Result.new(
        original_question: normalized_question,
        expanded_query: expanded_query,
        model: chat_result.model || model,
        usage: chat_result.usage,
        duration_ms: elapsed_ms(started_at)
      )
    rescue Error
      raise
    rescue Ai::ChatCompletionService::Error => error
      raise GenerationError,
            "Não foi possível expandir a consulta: #{error.message}"
    rescue StandardError => error
      raise Error,
            "Falha inesperada na expansão da consulta: #{error.message}"
    end

    private

    attr_reader(
      :question,
      :model,
      :chat_completion_service
    )

    def validate!
      return if question.is_a?(String) && question.strip.present?

      raise InvalidQuestionError,
            "A pergunta deve ser uma string não vazia"
    end

    def normalized_question
      @normalized_question ||= question.strip
    end

    def generate_expansion
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
        Você transforma perguntas em consultas de busca para um sistema RAG.

        Sua tarefa é ampliar a pergunta com termos técnicos, sinônimos,
        conceitos relacionados e possíveis critérios de busca.

        Regras:
        - Preserve a intenção original.
        - Não responda à pergunta.
        - Não invente fatos específicos.
        - Não use listas.
        - Retorne apenas uma consulta expandida.
        - Use no máximo 60 palavras.
        - Escreva em português.
      PROMPT
    end

    def extract_expanded_query(chat_result)
      chat_result.content.to_s.strip
    end

    def validate_expanded_query!(expanded_query)
      return if expanded_query.present?

      raise InvalidResponseError,
            "O modelo retornou uma consulta expandida vazia"
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_ms(started_at)
      ((monotonic_time - started_at) * 1_000).round(2)
    end
  end
end
