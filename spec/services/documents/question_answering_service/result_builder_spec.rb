require "rails_helper"

RSpec.describe Documents::QuestionAnsweringService::ResultBuilder do
  def groundedness_double_class
    @groundedness_double_class ||= Struct.new(:grounded, :refused, keyword_init: true)
  end

  def confidence_double_class
    @confidence_double_class ||= Struct.new(:score, :level, keyword_init: true)
  end

  def citation_result_double_class
    @citation_result_double_class ||= Struct.new(:citations, :citation_coverage, :cited_chunk_ids, keyword_init: true)
  end

  let(:document) { create(:document, title: "Manual", content: "Conteúdo.") }
  let(:chunk) { document.document_chunks.create!(content: "O prazo é de doze meses.", position: 0, embedding: Array.new(1536, 0.01)) }

  def build_context
    Documents::Pipeline::AnswerContext.new(
      question: "qual o prazo?",
      account_id: nil,
      conversation_history: [],
      config: nil,
      on_delta: nil,
      started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ).tap do |context|
      context.normalized_question = "qual o prazo?"
      context.effective_question = "Qual o prazo da apólice?"
    end
  end

  def build_search_result
    Documents::MmrService::Result.new(
      chunk: chunk, distance: 0.1, similarity: 0.9, position: 1, original_position: 1,
      vector_position: 1, text_position: nil, text_score: 0.0, normalized_text_score: 0.0,
      hybrid_score: 0.9, multi_query_score: nil, matched_queries: [], query_match_count: 1,
      best_query_position: 1, vector_score: 0.9, lexical_score: 0.0, position_score: 1.0,
      rerank_score: 0.9, matched_terms: [], cross_encoder_score: nil, cross_encoder_reason: nil,
      combined_score: nil, mmr_score: 0.9, redundancy_score: 0.0
    )
  end

  def build_retrieval_result(search_result)
    Documents::RetrievalPipelineService::Result.new(
      results: [ search_result ], reranked_results: [ search_result ], cross_encoder_results: [ search_result ],
      cross_encoder: nil, context_chunks: [ chunk ], compressed_chunks: [ chunk ], parent_retrieval: nil,
      context_compression: nil, query_embedding: Array.new(1536, 0.01), original_question: "qual o prazo?",
      search_query: "prazo apólice", queries: [ "prazo apólice" ], query_expansion: nil, multi_query: nil,
      metadata_filters: Documents::MetadataFilters.empty, metrics: {}, stage_failures: [], duration_ms: 12.0
    )
  end

  it "success builds a Result with sources derived from the retrieval results" do
    context = build_context
    search_result = build_search_result

    chat_result = Ai::ChatCompletionService::Result.new(
      content: "O prazo é de doze meses [FONTE 1].", model: "fake-model", finish_reason: "stop",
      usage: { total_tokens: 20 }, prompt_tokens: 15, completion_tokens: 5, total_tokens: 20, duration_ms: 3.0
    )

    result = Documents::QuestionAnsweringService::ResultBuilder.success(
      context: context,
      chat_result: chat_result,
      retrieval_result: build_retrieval_result(search_result),
      citation_result: citation_result_double_class.new(
        citations: [], citation_coverage: 1.0, cited_chunk_ids: [ chunk.id ]
      ),
      groundedness_result: groundedness_double_class.new(grounded: true, refused: false),
      hallucination_result: nil,
      confidence_result: confidence_double_class.new(score: 0.88, level: "high")
    )

    expect(result.effective_question).to eq("Qual o prazo da apólice?")
    expect(result.answer).to eq("O prazo é de doze meses [FONTE 1].")
    expect(result.sources.size).to eq(1)
    expect(result.sources.first.chunk_id).to eq(chunk.id)
    expect(result.sources.first.cited).to be_truthy
    expect(result.confidence_score).to eq(0.88)
    expect(result.grounded).to be_truthy
    expect(result.refused).to be_falsey
    expect(result.cache_hit).to eq(false)
  end

  it "no_evidence builds a refused, grounded result with no sources" do
    context = build_context
    error = Documents::RetrievalPipelineService::NoRelevantResultsError.new(
      "Nenhum conteúdo relevante foi encontrado",
      search_query: "prazo apólice",
      duration_ms: 8.0
    )

    result = Documents::QuestionAnsweringService::ResultBuilder.no_evidence(context: context, error: error)

    expect(result.answer).to eq(Documents::QuestionAnsweringService::NO_EVIDENCE_ANSWER)
    expect(result.sources).to be_empty
    expect(result.grounded).to be_truthy
    expect(result.refused).to be_truthy
    expect(result.search_query).to eq("prazo apólice")
    expect(result.retrieval_duration_ms).to eq(8.0)
  end

  it "cache_hit builds a result from the cached entry without sources" do
    context = build_context
    entry = create(:rag_semantic_cache_entry,
      question: "qual o prazo?",
      answer: "Resposta em cache.", model: "fake-model", confidence_score: 0.95,
      confidence_level: "high", expires_at: 1.hour.from_now
    )
    cache_hit = Documents::SemanticCacheLookupService::Result.new(entry: entry, similarity: 0.99)

    result = Documents::QuestionAnsweringService::ResultBuilder.cache_hit(context: context, cache_hit: cache_hit)

    expect(result.answer).to eq("Resposta em cache.")
    expect(result.cache_hit).to be_truthy
    expect(result.cache_similarity).to be_within(0.0001).of(0.99)
    expect(result.confidence_score).to eq(0.95)
    expect(result.sources).to be_empty
  end
end
