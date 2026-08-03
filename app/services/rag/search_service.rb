module Rag
  class SearchService
    DEFAULT_LIMIT = 3

    class Error < StandardError; end

    def self.call(question:, limit: DEFAULT_LIMIT)
      new(
        question: question,
        limit: limit
      ).call
    end

    def initialize(question:, limit:)
      @question = question.to_s.strip
      @limit = limit.to_i
    end

    def call
      validate!

      question_embedding = Ai::EmbeddingService.call(@question)

      DocumentChunk
        .where.not(embedding: nil)
        .nearest_neighbors(
          :embedding,
          question_embedding,
          distance: "cosine"
        )
        .first(@limit)
    end

    private

    def validate!
      if @question.blank?
        raise Error, "A pergunta não pode estar vazia"
      end

      unless @limit.positive?
        raise Error, "O limite deve ser maior que zero"
      end
    end
  end
end
