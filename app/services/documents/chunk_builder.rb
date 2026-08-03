module Documents
  class ChunkBuilder
    DEFAULT_SEPARATOR = "\n\n"

    attr_reader :max_tokens, :separator, :token_count

    def initialize(
      max_tokens:,
      separator: DEFAULT_SEPARATOR,
      tokenizer: Ai::Tokenizer
    )
      @max_tokens = max_tokens
      @separator = separator
      @tokenizer = tokenizer

      reset
    end

    def add(text)
      normalized_text = normalize(text)

      return false if normalized_text.empty?

      candidate = build_candidate(normalized_text)
      candidate_token_count = calculate_token_count(candidate)

      return false if candidate_token_count > max_tokens

      @text = candidate
      @token_count = candidate_token_count

      true
    end

    def fits?(text)
      normalized_text = normalize(text)

      return true if normalized_text.empty?

      candidate = build_candidate(normalized_text)

      calculate_token_count(candidate) <= max_tokens
    end

    def empty?
      @text.empty?
    end

    def present?
      !empty?
    end

    def text
      @text.dup
    end

    def reset
      @text = +""
      @token_count = 0

      self
    end

    private

    def build_candidate(new_text)
      return new_text if empty?

      "#{@text}#{separator}#{new_text}"
    end

    def normalize(text)
      text.to_s.strip
    end

    def calculate_token_count(text)
      @tokenizer.count(text)
    end
  end
end

