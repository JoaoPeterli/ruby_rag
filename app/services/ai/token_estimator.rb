# frozen_string_literal: true

module Ai
  # Aproximação heurística (não é um tokenizador real como tiktoken).
  # Para modelos GPT em português, ~4 caracteres por token é uma média
  # razoável, mas pode variar bastante conforme o texto.
  class TokenEstimator
    CHARS_PER_TOKEN = 4.0

    def self.estimate(text)
      (text.to_s.length / CHARS_PER_TOKEN).ceil
    end

    def self.characters_for(tokens)
      (tokens.to_f * CHARS_PER_TOKEN).floor
    end
  end
end
