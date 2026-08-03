module Ai
  class Tokenizer
    MODEL = "text-embedding-3-small"

    class Error < StandardError; end

    def self.count(text)
      new.count(text)
    end

    def self.encode(text)
      new.encode(text)
    end

    def self.decode(tokens)
      new.decode(tokens)
    end

    def initialize(model: MODEL)
      @encoder = Tiktoken.encoding_for_model(model)
    rescue StandardError => error
      raise Error, "Não foi possível carregar o tokenizer: #{error.message}"
    end

    def count(text)
      encode(text).length
    end

    def encode(text)
      @encoder.encode(text.to_s)
    rescue StandardError => error
      raise Error, "Não foi possível tokenizar o texto: #{error.message}"
    end

    def decode(tokens)
      @encoder.decode(Array(tokens))
    rescue StandardError => error
      raise Error, "Não foi possível decodificar os tokens: #{error.message}"
    end
  end
end
