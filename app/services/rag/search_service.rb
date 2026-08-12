module Rag
  class SearchService
    DEFAULT_LIMIT = 3

    Result = Data.define(:chunk, :distance)

    class Error < StandardError; end

    def self.call(question:, limit: DEFAULT_LIMIT, vector_store: Ai::VectorStoreService.default)
      new(
        question: question,
        limit: limit,
        vector_store: vector_store
      ).call
    end

    def initialize(question:, limit:, vector_store: Ai::VectorStoreService.default)
      @question = question.to_s.strip
      @limit = limit.to_i
      @vector_store = vector_store
    end

    def call
      validate!

      question_embedding = Ai::EmbeddingService.call(texts: [ @question ]).first

      points =
        @vector_store.search(
          collection: Ai::Configuration::QDRANT_DOCUMENT_CHUNKS_COLLECTION,
          vector: question_embedding,
          limit: @limit
        )

      chunks_by_id = DocumentChunk.where(id: points.map(&:id)).index_by(&:id)

      points.filter_map do |point|
        chunk = chunks_by_id[point.id]

        next unless chunk

        Result.new(chunk: chunk, distance: 1.0 - point.score.to_f)
      end
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
