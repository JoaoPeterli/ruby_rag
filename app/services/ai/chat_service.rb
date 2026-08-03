module Ai
  class ChatService
    MODEL = "gpt-4.1-mini".freeze

    class Error < StandardError; end

    def self.call(prompt)
      new(prompt).call
    end

    def initialize(prompt)
      @prompt = prompt
    end

    def call
      response = OPENAI_CLIENT.responses.create(
        model: MODEL,
        input: @prompt
      )

      response.output_text
    rescue StandardError => e
      Rails.logger.error("[ChatService] #{e.class}: #{e.message}")
      raise Error, "Erro ao gerar resposta"
    end
  end
end
