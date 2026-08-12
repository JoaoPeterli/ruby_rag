require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::Answering::BuildResultStep do
  let(:document) { create(:document) }
  let(:chunk) { document.document_chunks.create!(content: "Conteúdo do chunk.", position: 0, embedding: Array.new(1536, 0.01)) }

  def search_result
    Documents::MmrService::Result.new(
      chunk: chunk, distance: 0.1, similarity: 0.9, position: 1, original_position: 1,
      vector_position: 1, text_position: nil, text_score: 0.0, normalized_text_score: 0.0,
      hybrid_score: 0.9, multi_query_score: nil, matched_queries: [], query_match_count: 1,
      best_query_position: 1, vector_score: 0.9, lexical_score: 0.0, position_score: 1.0,
      rerank_score: 0.9, matched_terms: [], cross_encoder_score: nil, cross_encoder_reason: nil,
      combined_score: nil, mmr_score: 0.9, redundancy_score: 0.0
    )
  end

  def retrieval_result
    Documents::RetrievalPipelineService::Result.new(
      results: [ search_result ], reranked_results: [], cross_encoder_results: [], cross_encoder: nil,
      context_chunks: [ chunk ], compressed_chunks: [ chunk ], parent_retrieval: nil,
      context_compression: nil, query_embedding: Array.new(1536, 0.01), original_question: "pergunta",
      search_query: "pergunta", queries: [ "pergunta" ], query_expansion: nil, multi_query: nil,
      metadata_filters: Documents::MetadataFilters.empty, metrics: {}, stage_failures: [], duration_ms: 5.0
    )
  end

  def citation_result
    Documents::CitationEngine::Result.new(
      answer: "resposta [FONTE 1]",
      citations: [ Documents::CitationEngine::Citation.new(source_number: 1, chunk_id: chunk.id, document_id: document.id, position: 0) ],
      cited_source_numbers: [ 1 ], uncited_source_numbers: [], citation_count: 1, source_count: 1,
      citation_coverage: 1.0, duration_ms: 1.0
    )
  end

  def build_context
    config = Documents::QuestionAnsweringService::Config.new(
      **Documents::QuestionAnsweringService::Config.members.index_with { nil }
    )

    context = Documents::Pipeline::AnswerContext.new(
      question: "pergunta", account_id: nil, conversation_history: [],
      config: config, on_delta: nil, started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
    )
    context.normalized_question = "pergunta"
    context.effective_question = "pergunta"
    context.chat_result = Ai::ChatCompletionService::Result.new(
      content: "resposta [FONTE 1]", model: "fake-model", finish_reason: "stop",
      usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 },
      prompt_tokens: 1, completion_tokens: 1, total_tokens: 2, duration_ms: 1.0
    )
    context.retrieval_result = retrieval_result
    context.citation_result = citation_result
    context.groundedness_result = Documents::GroundednessCheckService::Result.new(grounded: true, refused: false, citation_count: 1, reason: nil)
    context.hallucination_result = Documents::HallucinationCheckService::Result.new(
      verdicts: [], supported_count: 0, unsupported_count: 0, hallucination_rate: 0.0, model: "m", duration_ms: 1.0
    )
    context.confidence_result = Documents::ConfidenceScoreService::Result.new(score: 0.8, level: :high, components: {})
    context
  end

  it "builds the final QuestionAnsweringService::Result from every collected signal" do
    context = build_context
    Documents::Pipeline::Steps::Answering::BuildResultStep.call(context: context)

    result = context.result
    expect(result).to be_a(Documents::QuestionAnsweringService::Result)
    expect(result.answer).to eq("resposta [FONTE 1]")
    expect(result.sources.size).to eq(1)
    expect(result.sources.first.chunk_id).to eq(chunk.id)
    expect(result.sources.first.cited).to be_truthy
    expect(result.citation_coverage).to eq(1.0)
    expect(result.grounded).to be_truthy
    expect(result.refused).to be_falsey
    expect(result.confidence_score).to be_within(0.0001).of(0.8)
    expect(result.confidence_level).to eq(:high)
    expect(result.cache_hit).to be_falsey
    expect(result.rag_query_id).to be_nil
  end

  it "does nothing when context.result is already set" do
    context = build_context
    context.result = :already_resolved

    Documents::Pipeline::Steps::Answering::BuildResultStep.call(context: context)

    expect(context.result).to eq(:already_resolved)
  end
end
