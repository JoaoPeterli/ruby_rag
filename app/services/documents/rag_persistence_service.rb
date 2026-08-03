# frozen_string_literal: true

module Documents
  class RagPersistenceService
    class Error < StandardError; end

    def self.call(...)
      new(...).call
    end

    def initialize(qa_result:, retrieval_result: nil, account_id: nil)
      @qa_result = qa_result
      @retrieval_result = retrieval_result
      @account_id = account_id
    end

    def call
      ActiveRecord::Base.transaction do
        rag_query = create_rag_query
        create_retrieval_results(rag_query)
        create_rag_answer(rag_query)

        rag_query
      end
    rescue StandardError => error
      raise Error, "Não foi possível persistir a consulta: #{error.message}"
    end

    private

    attr_reader :qa_result, :retrieval_result, :account_id

    def create_rag_query
      RagQuery.create!(
        question: qa_result.question,
        normalized_question: qa_result.question,
        search_query: qa_result.search_query,
        status: "completed",
        duration_ms: qa_result.duration_ms,
        total_tokens: qa_result.total_tokens,
        metrics: retrieval_result&.metrics || {},
        cache_hit: !!qa_result.cache_hit,
        account_id: account_id
      )
    end

    def create_retrieval_results(rag_query)
      qa_result.sources.each do |source|
        RagRetrievalResult.create!(
          rag_query: rag_query,
          document_chunk_id: source.chunk_id,
          position: source.position,
          cited: !!source.cited,
          hybrid_score: source.hybrid_score,
          rerank_score: source.rerank_score,
          cross_encoder_score: source.cross_encoder_score,
          combined_score: source.combined_score,
          mmr_score: source.mmr_score
        )
      end
    end

    def create_rag_answer(rag_query)
      RagAnswer.create!(
        rag_query: rag_query,
        answer: qa_result.answer,
        model: qa_result.model,
        grounded: qa_result.grounded,
        refused: qa_result.refused,
        citation_coverage: qa_result.citation_coverage,
        hallucination_rate: qa_result.hallucination_check&.hallucination_rate,
        confidence_score: qa_result.confidence_score,
        confidence_level: qa_result.confidence_level&.to_s,
        prompt_tokens: qa_result.prompt_tokens,
        completion_tokens: qa_result.completion_tokens,
        total_tokens: qa_result.total_tokens
      )
    end
  end
end
