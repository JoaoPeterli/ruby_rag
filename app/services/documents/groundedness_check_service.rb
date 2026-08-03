# frozen_string_literal: true

module Documents
  class GroundednessCheckService
    REFUSAL_PATTERN =
      /não encontrei informações suficientes/i

    Result = Data.define(
      :grounded,
      :refused,
      :citation_count,
      :reason
    )

    class Error < StandardError; end
    class InvalidAnswerError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(answer:, citation_count:)
      @answer = answer
      @citation_count = citation_count
    end

    def call
      validate!

      refused = answer.match?(REFUSAL_PATTERN)
      cited = citation_count.to_i.positive?
      grounded = refused || cited

      Result.new(
        grounded: grounded,
        refused: refused,
        citation_count: citation_count.to_i,
        reason: grounded ? nil : ungrounded_reason
      )
    end

    private

    attr_reader :answer, :citation_count

    def validate!
      return if answer.is_a?(String)

      raise InvalidAnswerError, "answer deve ser uma string"
    end

    def ungrounded_reason
      "A resposta não cita nenhuma fonte e não recusou explicitamente " \
        "por falta de informação — possível alucinação."
    end
  end
end
