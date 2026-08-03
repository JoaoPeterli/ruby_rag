# frozen_string_literal: true

module Documents
  # Achata Documents::QuestionAnsweringService::Result pra JSON,
  # compartilhado pelos endpoints síncrono e de streaming da API.
  class QuestionAnsweringResultSerializer
    SOURCE_CONTENT_TRUNCATE_LENGTH = 280

    def self.call(...)
      new(...).call
    end

    def initialize(result:)
      @result = result
    end

    def call
      {
        question: result.question,
        effective_question: result.effective_question,
        answer: result.answer,
        sources: result.sources.map { |source| serialize_source(source) },
        citations: result.citations.map { |citation| serialize_citation(citation) },
        citation_coverage: result.citation_coverage,
        grounded: result.grounded,
        refused: result.refused,
        confidence_score: result.confidence_score,
        confidence_level: result.confidence_level,
        cache_hit: result.cache_hit,
        cache_similarity: result.cache_similarity,
        model: result.model,
        total_tokens: result.total_tokens,
        retrieval_duration_ms: result.retrieval_duration_ms,
        duration_ms: result.duration_ms,
        rag_query_id: result.rag_query_id,
        rag_answer_id: result.rag_answer_id
      }
    end

    private

    attr_reader :result

    def serialize_source(source)
      {
        chunk_id: source.chunk_id,
        document_id: source.document_id,
        content: source.content.to_s.truncate(SOURCE_CONTENT_TRUNCATE_LENGTH),
        position: source.position,
        cited: source.cited,
        hybrid_score: source.hybrid_score,
        rerank_score: source.rerank_score,
        cross_encoder_score: source.cross_encoder_score,
        combined_score: source.combined_score,
        mmr_score: source.mmr_score
      }
    end

    def serialize_citation(citation)
      {
        source_number: citation.source_number,
        chunk_id: citation.chunk_id,
        document_id: citation.document_id,
        position: citation.position
      }
    end
  end
end
