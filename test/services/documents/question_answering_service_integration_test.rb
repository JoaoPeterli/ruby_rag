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
end
