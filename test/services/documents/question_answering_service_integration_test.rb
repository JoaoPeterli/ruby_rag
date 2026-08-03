require "test_helper"

# Testes de integração que fixam (via DI) apenas as bordas externas
# (chat completion, retrieval pipeline) e deixam o resto do
# QuestionAnsweringService rodar de verdade: construção de contexto,
# prompt, citation engine, groundedness, confidence e montagem de
# Source. Nada aqui bate na API da OpenAI.
class Documents::QuestionAnsweringServiceIntegrationTest < ActiveSupport::TestCase
  class RaisingRetrievalPipeline
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

  test "answers gracefully instead of raising when the pipeline finds nothing" do
    result = Documents::QuestionAnsweringService.call(
      question: "pergunta sem relação com a base",
      persist_enabled: false,
      retrieval_pipeline: RaisingRetrievalPipeline
    )

    assert result.refused
    assert result.grounded
    assert_equal Documents::QuestionAnsweringService::NO_EVIDENCE_ANSWER, result.answer
    assert_empty result.sources
    assert_equal "pergunta reescrita", result.search_query
    assert_equal 42.0, result.retrieval_duration_ms
  end

  test "produces a well-formed answer end to end with a faked retrieval result and LLM" do
    document = Document.create!(
      title: "Manual de Teste",
      content: "Conteudo de teste do documento.",
      status: "completed",
      account: Account.create!(name: "Conta de Teste")
    )

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

    assert_equal "O sistema busca a apolice antes da averbacao [FONTE 1].", result.answer
    assert_equal 1, result.sources.size
    assert_equal chunk.id, result.sources.first.chunk_id
    assert result.sources.first.cited
    assert_equal 1.0, result.citation_coverage
    assert_not result.refused
  end

  test "persists the rag_query scoped to the given account" do
    account = Account.create!(name: "Conta de Persistencia")

    result = Documents::QuestionAnsweringService.call(
      question: "pergunta sem relação com a base",
      account_id: account.id,
      persist_enabled: true,
      retrieval_pipeline: RaisingRetrievalPipeline
    )

    assert result.rag_query_id.present?
    assert result.rag_answer_id.present?

    rag_query = RagQuery.find(result.rag_query_id)
    assert_equal account.id, rag_query.account_id
  end

  test "returns a cached answer without calling the LLM when the semantic cache hits" do
    account = Account.create!(name: "Conta de Cache")
    embedding = Array.new(1536, 0.02)

    RagSemanticCacheEntry.create!(
      question: "pergunta anterior",
      question_embedding: embedding,
      answer: "Resposta em cache.",
      model: "fake-model",
      confidence_score: 0.9,
      confidence_level: "high",
      expires_at: 1.hour.from_now,
      account_id: account.id
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

    assert result.cache_hit
    assert_equal "Resposta em cache.", result.answer
    assert_in_delta 1.0, result.cache_similarity, 0.001
  end

  test "streams deltas through the given block and returns the accumulated answer" do
    document = Document.create!(
      title: "Manual de Teste",
      content: "Conteudo de teste do documento.",
      status: "completed",
      account: Account.create!(name: "Conta de Streaming")
    )

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

    assert_equal [ "O sistema ", "busca a apolice." ], received_deltas
    assert_equal "O sistema busca a apolice.", result.answer
  end
end
