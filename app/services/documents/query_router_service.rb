# frozen_string_literal: true

require "json"

module Documents
  class QueryRouterService
    DEFAULT_MODEL = Ai::Configuration.chat_model
    DEFAULT_TEMPERATURE = 0.0

    CATEGORIES = %w[
      factual
      comparacao
      resumo
      procedimento
      documento_especifico
      fora_da_base
    ].freeze

    Result = Data.define(
      :category,
      :reason,
      :model,
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

      chat_result = classify
      parsed = parse_response(chat_result.content)

      Result.new(
        category: normalize_category(parsed["category"]),
        reason: parsed["reason"].to_s.strip.presence || "Sem justificativa.",
        model: chat_result.model || model,
        duration_ms: elapsed_ms(started_at)
      )
    rescue Error
      raise
    rescue Ai::ChatCompletionService::Error => error
      raise GenerationError,
            "Não foi possível classificar a pergunta: #{error.message}"
    rescue JSON::ParserError => error
      raise InvalidResponseError,
            "O modelo retornou um JSON inválido: #{error.message}"
    rescue StandardError => error
      raise Error,
            "Falha inesperada no Query Router: #{error.message}"
    end

    private

    attr_reader :question, :model, :chat_completion_service

    def validate!
      return if question.is_a?(String) && question.strip.present?

      raise InvalidQuestionError, "question deve ser uma string não vazia"
    end

    def normalized_question
      @normalized_question ||= question.strip
    end

    def classify
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
        Você classifica perguntas de um sistema RAG em uma categoria.

        Categorias disponíveis:

        - factual: pergunta direta sobre um fato ou dado específico.
        - comparacao: pede para comparar duas ou mais coisas.
        - resumo: pede um resumo ou visão geral de um tema ou documento.
        - procedimento: pergunta sobre como executar um processo passo a passo.
        - documento_especifico: menciona ou depende de um documento específico.
        - fora_da_base: claramente não relacionado ao domínio de documentos
          técnicos, apólices, seguros ou ao sistema descrito nos documentos.

        Regras obrigatórias:

        - Escolha exatamente uma categoria da lista.
        - Não responda à pergunta.
        - Retorne somente JSON válido no formato:

        {
          "category": "factual",
          "reason": "Explicação curta"
        }
      PROMPT
    end

    def parse_response(content)
      sanitized =
        content.to_s
          .sub(/\A```(?:json)?\s*/i, "")
          .sub(/\s*```\z/, "")
          .strip

      parsed = JSON.parse(sanitized)

      unless parsed.is_a?(Hash)
        raise InvalidResponseError, "A resposta precisa ser um objeto JSON"
      end

      parsed
    end

    def normalize_category(value)
      category = value.to_s.strip.downcase

      CATEGORIES.include?(category) ? category : "factual"
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_ms(started_at)
      ((monotonic_time - started_at) * 1_000).round(2)
    end
  end
end
