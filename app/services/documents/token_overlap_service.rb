module Documents
  class TokenOverlapService
    DEFAULT_OVERLAP_TOKENS = 75
    DEFAULT_SEPARATOR = "\n\n"

    SEPARATORS = [
      /\n{2,}/,          # Parágrafos
      /(?<=[.!?])\s+/,   # Frases
      /\n+/,              # Linhas
      /\s+/               # Palavras
    ].freeze

    def self.call(
      chunks,
      overlap_tokens: DEFAULT_OVERLAP_TOKENS,
      tokenizer: Ai::Tokenizer
    )
      new(
        chunks,
        overlap_tokens: overlap_tokens,
        tokenizer: tokenizer
      ).call
    end

    def initialize(chunks, overlap_tokens:, tokenizer:)
      @chunks = Array(chunks)
      @overlap_tokens = overlap_tokens
      @tokenizer = tokenizer
    end

    def call
      chunks = normalized_chunks

      return [] if chunks.empty?

      result = [
        Documents::ChunkWithOverlap.new(
          content: chunks.first
        )
      ]

      chunks.each_cons(2) do |previous_chunk, current_chunk|
        result << Documents::ChunkWithOverlap.new(
          content: current_chunk,
          overlap: build_overlap(previous_chunk)
        )
      end

      result
    end

    private

    def normalized_chunks
      @chunks
        .map { |chunk| chunk.to_s.strip }
        .reject(&:empty?)
    end

    def build_overlap(text)
      SEPARATORS.each do |separator|
        overlap = extract_complete_parts(text, separator)

        return overlap unless overlap.empty?
      end

      hard_token_overlap(text)
    end

    def extract_complete_parts(text, separator)
      parts = text
        .split(separator)
        .map(&:strip)
        .reject(&:empty?)

      selected_parts = []

      parts.reverse_each do |part|
        candidate = ([part] + selected_parts)
          .join(DEFAULT_SEPARATOR)

        break if token_count(candidate) > @overlap_tokens

        selected_parts.unshift(part)
      end

      selected_parts.join(DEFAULT_SEPARATOR)
    end

    def hard_token_overlap(text)
      tokens = @tokenizer.encode(text)
      overlap_tokens = tokens.last(@overlap_tokens)

      @tokenizer.decode(overlap_tokens)
    end

    def token_count(text)
      @tokenizer.count(text)
    end
  end
end
