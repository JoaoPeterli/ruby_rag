# frozen_string_literal: true

module Documents
  class SemanticCacheStoreService
    DEFAULT_TTL = 24.hours

    class Error < StandardError; end
    class InvalidQuestionError < Error; end
    class InvalidEmbeddingError < Error; end
    class InvalidResultError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(
      question:,
      question_embedding:,
      qa_result:,
      ttl: DEFAULT_TTL,
      account_id: nil,
      vector_store: Ai::VectorStoreService.default
    )
      @question = question
      @question_embedding = question_embedding
      @qa_result = qa_result
      @ttl = ttl
      @account_id = account_id
      @vector_store = vector_store
    end

    def call
      validate!

      entry = RagSemanticCacheEntry.create!(
        question: question,
        answer: qa_result.answer,
        sources: serialize_sources(qa_result.sources),
        model: qa_result.model,
        confidence_score: qa_result.confidence_score,
        confidence_level: qa_result.confidence_level&.to_s,
        expires_at: Time.current + ttl,
        account_id: account_id
      )

      vector_store.upsert(
        collection: Ai::Configuration::QDRANT_SEMANTIC_CACHE_COLLECTION,
        id: entry.id,
        vector: question_embedding,
        payload: { account_id: account_id }
      )

      entry
    rescue Error
      raise
    rescue StandardError => error
      raise Error, "Não foi possível gravar o cache semântico: #{error.message}"
    end

    private

    attr_reader :question, :question_embedding, :qa_result, :ttl, :account_id, :vector_store

    def validate!
      unless question.is_a?(String) && question.strip.present?
        raise InvalidQuestionError, "question deve ser uma string não vazia"
      end

      unless question_embedding.is_a?(Array) && question_embedding.any?
        raise InvalidEmbeddingError,
              "question_embedding deve ser uma lista de números não vazia"
      end

      return if qa_result.respond_to?(:answer) && qa_result.answer.present?

      raise InvalidResultError,
            "qa_result deve possuir uma resposta não vazia"
    end

    def serialize_sources(sources)
      Array(sources).map do |source|
        {
          chunk_id: source.chunk_id,
          document_id: source.document_id,
          position: source.position
        }
      end
    end
  end
end
