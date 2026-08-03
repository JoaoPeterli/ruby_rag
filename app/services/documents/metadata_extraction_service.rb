# frozen_string_literal: true

require "json"

module Documents
  class MetadataExtractionService
    DEFAULT_MODEL = Ai::Configuration.chat_model
    DEFAULT_TEMPERATURE = 0.0

    ALLOWED_FIELDS = %w[
      ramo
      seguradora
      cliente
      tipo_documento
      vigencia_ano
    ].freeze

    Result = Data.define(
      :filters,
      :raw_content,
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

      chat_result = generate_filters
      raw_content = chat_result.content.to_s.strip

      parsed_filters = parse_response(raw_content)
      filters = build_filters(parsed_filters)

      Result.new(
        filters: filters,
        raw_content: raw_content,
        model: chat_result.model || model,
        usage: chat_result.usage,
        duration_ms: elapsed_ms(started_at)
      )
    rescue Error
      raise
    rescue Ai::ChatCompletionService::Error => error
      raise GenerationError,
            "Não foi possível extrair os metadados: #{error.message}"
    rescue JSON::ParserError => error
      raise InvalidResponseError,
            "O modelo retornou um JSON inválido: #{error.message}"
    rescue StandardError => error
      raise Error,
            "Falha inesperada na extração de metadados: #{error.message}"
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

    def generate_filters
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
        Você extrai filtros de metadados para busca em documentos.

        Campos disponíveis:

        - ramo: ramo ou modalidade de seguro
        - seguradora: nome da seguradora
        - cliente: nome do cliente ou empresa
        - tipo_documento: tipo do documento, como apolice, manual, contrato ou endosso
        - vigencia_ano: ano da vigência como número inteiro

        Regras obrigatórias:

        - Retorne somente um objeto JSON válido.
        - Não responda à pergunta.
        - Não invente valores.
        - Inclua apenas campos explicitamente informados ou claramente identificáveis.
        - Não retorne campos vazios ou nulos.
        - Use os nomes exatos dos campos permitidos.
        - Para vigencia_ano, retorne apenas um número inteiro.

        Quando nenhum filtro puder ser extraído, retorne:

        {}
      PROMPT
    end

    def parse_response(content)
      sanitized = remove_code_fence(content)

      parsed = JSON.parse(sanitized)

      unless parsed.is_a?(Hash)
        raise InvalidResponseError,
              "A resposta precisa ser um objeto JSON"
      end

      parsed.slice(*ALLOWED_FIELDS)
    end

    def remove_code_fence(content)
      content
        .sub(/\A```(?:json)?\s*/i, "")
        .sub(/\s*```\z/, "")
        .strip
    end

    def build_filters(values)
      MetadataFilters.new(
        ramo: normalize_text(values["ramo"]),
        seguradora: normalize_text(values["seguradora"]),
        cliente: normalize_text(values["cliente"]),
        tipo_documento: normalize_text(
          values["tipo_documento"]
        ),
        vigencia_ano: normalize_year(values["vigencia_ano"]),
        metadata: {}
      )
    end

    def normalize_text(value)
      normalized = value.to_s.strip

      normalized.presence
    end

    def normalize_year(value)
      return if value.blank?

      year = Integer(value)

      return year if year.between?(1900, 2200)

      nil
    rescue ArgumentError, TypeError
      nil
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_ms(started_at)
      ((monotonic_time - started_at) * 1_000).round(2)
    end
  end
end
