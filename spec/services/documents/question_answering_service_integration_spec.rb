require "rails_helper"

# Testes de integração que fixam (via DI) apenas as bordas externas
# (chat completion, retrieval pipeline) e deixam o resto do
# QuestionAnsweringService rodar de verdade: construção de contexto,
# prompt, citation engine, groundedness, confidence e montagem de
# Source. Nada aqui bate na API da OpenAI.
RSpec.describe Documents::QuestionAnsweringService do
  def raising_retrieval_pipeline_class
    Class.new do
      def self.call(**)
        raise Documents::RetrievalPipelineService::NoRelevantResultsError.new(
          "Nenhum conteúdo relevante foi encontrado para a pergunta",
          search_query: "pergunta reescrita",
          queries: [ "pergunta reescrita" ],
          metrics: { hybrid_search: 12.3 },
          stage_failures: [],
          duration_ms: 42.0
        )
      end
    end
  end

  it "answers gracefully instead of raising when the pipeline finds nothing" do
    result = Documents::QuestionAnsweringService.call(
      question: "pergunta sem relação com a base",
      persist_enabled: false,
      retrieval_pipeline: raising_retrieval_pipeline_class
    )

    expect(result.refused).to be_truthy
    expect(result.grounded).to be_truthy
    expect(result.answer).to eq(Documents::QuestionAnsweringService::NO_EVIDENCE_ANSWER)
    expect(result.sources).to be_empty
    expect(result.search_query).to eq("pergunta reescrita")
    expect(result.retrieval_duration_ms).to eq(42.0)
  end

  it "produces a well-formed answer end to end with a faked retrieval result and LLM" do
    document = create(:document, title: "Manual de Teste", content: "Conteudo de teste do documento.")

    chunk = document.document_chunks.create!(
      content: "O sistema busca uma apolice antes da averbacao.",
      position: 0,
      embedding: Array.new(1536, 0.01)
    )

    mmr_result = Documents::MmrService::Result.new(
      chunk: chunk,
      distance: 0.1,
      similarity: 0.9,
      position: 1,
      original_position: 1,
      vector_position: 1,
      text_position: nil,
      text_score: 0.0,
      normalized_text_score: 0.0,
      hybrid_score: 0.9,
      multi_query_score: nil,
      matched_queries: [],
      query_match_count: 1,
      best_query_position: 1,
      vector_score: 0.9,
      lexical_score: 0.0,
      position_score: 1.0,
      rerank_score: 0.9,
      matched_terms: [],
      cross_encoder_score: nil,
      cross_encoder_reason: nil,
      combined_score: nil,
      mmr_score: 0.9,
      redundancy_score: 0.0
    )

    retrieval_result = Documents::RetrievalPipelineService::Result.new(
      results: [ mmr_result ],
      reranked_results: [ mmr_result ],
      cross_encoder_results: [ mmr_result ],
      cross_encoder: nil,
      context_chunks: [ chunk ],
      compressed_chunks: [ chunk ],
      parent_retrieval: nil,
      context_compression: nil,
      query_embedding: Array.new(1536, 0.01),
      original_question: "Como o sistema busca uma apolice?",
      search_query: "Como o sistema busca uma apolice?",
      queries: [ "Como o sistema busca uma apolice?" ],
      query_expansion: nil,
      multi_query: nil,
      metadata_filters: Documents::MetadataFilters.empty,
      metrics: {},
      stage_failures: [],
      duration_ms: 10.0
    )

    fake_retrieval_pipeline = Class.new do
      define_singleton_method(:call) { |**_kwargs| retrieval_result }
    end

    chat_result = Ai::ChatCompletionService::Result.new(
      content: "O sistema busca a apolice antes da averbacao [FONTE 1].",
      model: "fake-model",
      finish_reason: "stop",
      usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
      prompt_tokens: 10,
      completion_tokens: 5,
      total_tokens: 15,
      duration_ms: 1.0
    )

    fake_chat_completion_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| chat_result }
    end

    result = Documents::QuestionAnsweringService.call(
      question: "Como o sistema busca uma apolice?",
      persist_enabled: false,
      hallucination_check_enabled: false,
      retrieval_pipeline: fake_retrieval_pipeline,
      chat_completion_service: fake_chat_completion_service
    )

    expect(result.answer).to eq("O sistema busca a apolice antes da averbacao [FONTE 1].")
    expect(result.sources.size).to eq(1)
    expect(result.sources.first.chunk_id).to eq(chunk.id)
    expect(result.sources.first.cited).to be_truthy
    expect(result.citation_coverage).to eq(1.0)
    expect(result.refused).to be_falsey
  end

  it "persists the rag_query scoped to the given account" do
    account = create(:account)

    result = Documents::QuestionAnsweringService.call(
      question: "pergunta sem relação com a base",
      account_id: account.id,
      persist_enabled: true,
      retrieval_pipeline: raising_retrieval_pipeline_class
    )

    expect(result.rag_query_id).to be_present
    expect(result.rag_answer_id).to be_present

    rag_query = RagQuery.find(result.rag_query_id)
    expect(rag_query.account_id).to eq(account.id)
  end

  it "returns a cached answer without calling the LLM when the semantic cache hits" do
    account = create(:account)
    embedding = Array.new(1536, 0.02)

    cached_entry = create(:rag_semantic_cache_entry, account_id: account.id)

    Ai::VectorStoreService.default.upsert(
      collection: Ai::Configuration::QDRANT_SEMANTIC_CACHE_COLLECTION,
      id: cached_entry.id,
      vector: embedding,
      payload: { account_id: account.id }
    )

    fake_embedding_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| [ embedding ] }
    end

    unreachable_chat_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise "não deveria ser chamado em cache hit" }
    end

    result = Documents::QuestionAnsweringService.call(
      question: "pergunta nova parecida",
      account_id: account.id,
      persist_enabled: false,
      semantic_cache_enabled: true,
      embedding_service: fake_embedding_service,
      chat_completion_service: unreachable_chat_service
    )

    expect(result.cache_hit).to be_truthy
    expect(result.answer).to eq(cached_entry.answer)
    expect(result.cache_similarity).to be_within(0.001).of(1.0)
  end

  it "streams deltas through the given block and returns the accumulated answer" do
    document = create(:document, title: "Manual de Teste", content: "Conteudo de teste do documento.")

    chunk = document.document_chunks.create!(
      content: "O sistema busca uma apolice antes da averbacao.",
      position: 0,
      embedding: Array.new(1536, 0.01)
    )

    mmr_result = Documents::MmrService::Result.new(
      chunk: chunk,
      distance: 0.1,
      similarity: 0.9,
      position: 1,
      original_position: 1,
      vector_position: 1,
      text_position: nil,
      text_score: 0.0,
      normalized_text_score: 0.0,
      hybrid_score: 0.9,
      multi_query_score: nil,
      matched_queries: [],
      query_match_count: 1,
      best_query_position: 1,
      vector_score: 0.9,
      lexical_score: 0.0,
      position_score: 1.0,
      rerank_score: 0.9,
      matched_terms: [],
      cross_encoder_score: nil,
      cross_encoder_reason: nil,
      combined_score: nil,
      mmr_score: 0.9,
      redundancy_score: 0.0
    )

    retrieval_result = Documents::RetrievalPipelineService::Result.new(
      results: [ mmr_result ],
      reranked_results: [ mmr_result ],
      cross_encoder_results: [ mmr_result ],
      cross_encoder: nil,
      context_chunks: [ chunk ],
      compressed_chunks: [ chunk ],
      parent_retrieval: nil,
      context_compression: nil,
      query_embedding: Array.new(1536, 0.01),
      original_question: "Como o sistema busca uma apolice?",
      search_query: "Como o sistema busca uma apolice?",
      queries: [ "Como o sistema busca uma apolice?" ],
      query_expansion: nil,
      multi_query: nil,
      metadata_filters: Documents::MetadataFilters.empty,
      metrics: {},
      stage_failures: [],
      duration_ms: 10.0
    )

    fake_retrieval_pipeline = Class.new do
      define_singleton_method(:call) { |**_kwargs| retrieval_result }
    end

    fake_chat_stream_service = Class.new do
      define_singleton_method(:call) do |**_kwargs, &on_delta|
        on_delta.call("O sistema ")
        on_delta.call("busca a apolice.")

        Ai::ChatCompletionService::Result.new(
          content: "O sistema busca a apolice.",
          model: "fake-model",
          finish_reason: "stop",
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
          prompt_tokens: 10,
          completion_tokens: 5,
          total_tokens: 15,
          duration_ms: 1.0
        )
      end
    end

    received_deltas = []

    result = Documents::QuestionAnsweringService.call(
      question: "Como o sistema busca uma apolice?",
      persist_enabled: false,
      citation_engine_enabled: false,
      groundedness_check_enabled: false,
      retrieval_pipeline: fake_retrieval_pipeline,
      chat_stream_service: fake_chat_stream_service
    ) { |delta| received_deltas << delta }

    expect(received_deltas).to eq([ "O sistema ", "busca a apolice." ])
    expect(result.answer).to eq("O sistema busca a apolice.")
  end
end
