module Documents
  class PackingService
    DEFAULT_MAX_TOKENS = 500
    DEFAULT_SEPARATOR = "\n\n"

    class ChunkTooLargeError < StandardError; end

    def self.call(
      chunks,
      max_tokens: DEFAULT_MAX_TOKENS,
      separator: DEFAULT_SEPARATOR,
      tokenizer: Ai::Tokenizer
    )
      new(
        chunks,
        max_tokens: max_tokens,
        separator: separator,
        tokenizer: tokenizer
      ).call
    end

    def initialize(
      chunks,
      max_tokens:,
      separator:,
      tokenizer:
    )
      @chunks = Array(chunks)
      @max_tokens = max_tokens
      @separator = separator
      @tokenizer = tokenizer
    end

    def call
      packed_chunks = []
      builder = build_chunk_builder

      normalized_chunks.each do |chunk|
        if builder.add(chunk)
          next
        end

        packed_chunks << build_result(builder) if builder.present?

        builder.reset

        unless builder.add(chunk)
          raise ChunkTooLargeError,
                oversized_chunk_message(chunk)
        end
      end

      packed_chunks << build_result(builder) if builder.present?

      packed_chunks
    end

    private

    def normalized_chunks
      @normalized_chunks ||= @chunks
        .map { |chunk| chunk.to_s.strip }
        .reject(&:empty?)
    end

    def build_chunk_builder
      Documents::ChunkBuilder.new(
        max_tokens: @max_tokens,
        separator: @separator,
        tokenizer: @tokenizer
      )
    end

    def build_result(builder)
      builder.text
    end

    def oversized_chunk_message(chunk)
      total_tokens = @tokenizer.count(chunk)

      "O trecho possui #{total_tokens} tokens, " \
        "mas o limite do PackingService é #{@max_tokens}. " \
        "Passe o conteúdo primeiro pelo RecursiveChunker."
    end
  end
end
