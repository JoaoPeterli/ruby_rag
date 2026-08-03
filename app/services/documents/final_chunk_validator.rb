module Documents
  class FinalChunkValidator
    DEFAULT_MAX_TOKENS = 500
    DEFAULT_SEPARATOR = "\n\n"

    class ContentTooLargeError < StandardError; end

    def self.call(
      chunks,
      max_tokens: DEFAULT_MAX_TOKENS,
      tokenizer: Ai::Tokenizer,
      separator: DEFAULT_SEPARATOR
    )
      new(
        chunks,
        max_tokens: max_tokens,
        tokenizer: tokenizer,
        separator: separator
      ).call
    end

    def initialize(chunks, max_tokens:, tokenizer:, separator:)
      @chunks = Array(chunks)
      @max_tokens = max_tokens
      @tokenizer = tokenizer
      @separator = separator
    end

    def call
      @chunks.map.with_index do |chunk, index|
        validate_chunk(chunk, index)
      end
    end

    private

    def validate_chunk(chunk, index)
      validate_type!(chunk)

      content = chunk.content
      overlap = chunk.overlap

      validate_content_size!(content, index)

      return content if overlap.empty?

      complete_text = join(overlap, content)

      return complete_text if token_count(complete_text) <= @max_tokens

      reduced_overlap = reduce_overlap(
        overlap,
        content
      )

      return content if reduced_overlap.empty?

      join(reduced_overlap, content)
    end

    def reduce_overlap(overlap, content)
      available_tokens = available_overlap_tokens(content)

      return "" if available_tokens <= 0

      overlap_tokens = @tokenizer.encode(overlap)

      while overlap_tokens.any?
        candidate_overlap = @tokenizer.decode(overlap_tokens)

        candidate_text = join(
          candidate_overlap,
          content
        )

        return candidate_overlap.strip if valid?(candidate_text)

        overlap_tokens.shift
      end

      ""
    end

    def available_overlap_tokens(content)
      content_tokens = token_count(content)

      @max_tokens - content_tokens
    end

    def validate_content_size!(content, index)
      total_tokens = token_count(content)

      return if total_tokens <= @max_tokens

      raise ContentTooLargeError,
            "O conteúdo principal do chunk #{index + 1} possui " \
            "#{total_tokens} tokens, mas o limite é #{@max_tokens}. " \
            "Reduza o limite utilizado no PackingService."
    end

    def validate_type!(chunk)
      return if chunk.is_a?(Documents::ChunkWithOverlap)

      raise ArgumentError,
            "Era esperado Documents::ChunkWithOverlap, " \
            "mas foi recebido #{chunk.class}."
    end

    def valid?(text)
      token_count(text) <= @max_tokens
    end

    def join(overlap, content)
      "#{overlap.to_s.strip}#{@separator}#{content.to_s.strip}"
    end

    def token_count(text)
      @tokenizer.count(text)
    end
  end
end
