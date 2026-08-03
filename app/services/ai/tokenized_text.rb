module Ai
  class TokenizedText
    attr_reader :text, :tokens

    def initialize(text)
      @text = text.to_s.strip
      @tokens = Tokenizer.count(@text)
    end

    def size
      @tokens
    end
  end
end
