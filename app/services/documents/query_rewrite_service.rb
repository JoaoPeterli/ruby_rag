# frozen_string_literal: true

module Documents
  class QueryRewriteService
    DEFAULT_MODEL = Ai::Configuration.chat_model
    DEFAULT_TEMPERATURE = 0.0
    DEFAULT_HISTORY_LIMIT = 6

    Result = Data.define(
      :original_question,
      :rewritten_question,
      :rewritten,
      :model,
      :duration_ms
    )

    class Error < StandardError; end
    class InvalidQuestionError < Error; end
    class GenerationError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(
      question:,
      history:,
      model: DEFAULT_MODEL,
      history_limit: DEFAULT_HISTORY_LIMIT,
      chat_completion_service: Ai::ChatCompletionService
    )
      @question = question
      @history = Array(history)
      @model = model
      @history_limit = history_limit
      @chat_completion_service = chat_completion_service
    end

    def call
      started_at = monotonic_time

      validate!

      return unchanged_result(started_at) if history.empty?

      chat_result = generate_rewrite
      rewritten_question = chat_result.content.to_s.strip

      Result.new(
        original_question: normalized_question,
        rewritten_question: rewritten_question.presence || normalized_question,
        rewritten:
          rewritten_question.present? &&
          rewritten_question != normalized_question,
        model: chat_result.model || model,
        duration_ms: elapsed_ms(started_at)
      )
    rescue Error
      raise
    rescue Ai::ChatCompletionService::Error => error
      raise GenerationError,
            "Não foi possível reescrever a pergunta: #{error.message}"
    rescue StandardError => error
      raise Error,
            "Falha inesperada na reescrita da pergunta: #{error.message}"
    end

    private

    attr_reader(
      :question,
      :history,
      :model,
      :history_limit,
      :chat_completion_service
    )

    def validate!
      return if question.is_a?(String) && question.strip.present?

      raise InvalidQuestionError, "question deve ser uma string não vazia"
    end

    def normalized_question
      @normalized_question ||= question.strip
    end

    def unchanged_result(started_at)
      Result.new(
        original_question: normalized_question,
        rewritten_question: normalized_question,
        rewritten: false,
        model: nil,
        duration_ms: elapsed_ms(started_at)
      )
    end

    def generate_rewrite
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
            content: user_prompt
          }
        ]
      )
    end

    def system_prompt
      <<~PROMPT
        Você reescreve perguntas de uma conversa para torná-las
        autossuficientes, sem depender do histórico para fazer sentido.

        Use o histórico apenas para resolver referências implícitas
        (pronomes, "isso", "aquele", elipses como "e o prazo?").

        Regras obrigatórias:

        - Não responda à pergunta.
        - Não adicione informações que não estejam na pergunta ou no
          histórico.
        - Se a pergunta atual já for autossuficiente, devolva-a sem
          nenhuma alteração.
        - Retorne apenas a pergunta reescrita, em uma linha, sem aspas
          e sem explicações.
      PROMPT
    end

    def user_prompt
      <<~PROMPT
        HISTÓRICO DA CONVERSA:

        #{format_history}

        PERGUNTA ATUAL:
        #{normalized_question}
      PROMPT
    end

    def format_history
      history.last(history_limit).map do |turn|
        "#{turn_role(turn)}: #{turn_content(turn)}"
      end.join("\n")
    end

    def turn_role(turn)
      (turn[:role] || turn["role"]).to_s
    end

    def turn_content(turn)
      (turn[:content] || turn["content"]).to_s
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_ms(started_at)
      ((monotonic_time - started_at) * 1_000).round(2)
    end
  end
end
