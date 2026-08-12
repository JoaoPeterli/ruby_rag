require "rails_helper"

# Testes de unidade focados em ramos NÃO cobertos por
# question_answering_service_integration_spec.rb (que já cobre: caminho
# sem evidência, caminho feliz completo com hallucination_check
# desligado, persistência por conta, cache semântico e streaming).
RSpec.describe Documents::QuestionAnsweringService do
  def build_mmr_result(chunk)
    Documents::MmrService::Result.new(
      chunk: chunk, distance: 0.1, similarity: 0.9, position: 1, original_position: 1,
      vector_position: 1, text_position: nil, text_score: 0.0, normalized_text_score: 0.0,
      hybrid_score: 0.9, multi_query_score: nil, matched_queries: [], query_match_count: 1,
      best_query_position: 1, vector_score: 0.9, lexical_score: 0.0, position_score: 1.0,
      rerank_score: 0.9, matched_terms: [], cross_encoder_score: nil, cross_encoder_reason: nil,
      combined_score: nil, mmr_score: 0.9, redundancy_score: 0.0
    )
  end

  def build_retrieval_result(chunk)
    mmr_result = build_mmr_result(chunk)

    Documents::RetrievalPipelineService::Result.new(
      results: [ mmr_result ], reranked_results: [ mmr_result ], cross_encoder_results: [ mmr_result ],
      cross_encoder: nil, context_chunks: [ chunk ], compressed_chunks: [ chunk ],
      parent_retrieval: nil, context_compression: nil, query_embedding: Array.new(1536, 0.01),
      original_question: "Como o sistema busca uma apolice?", search_query: "Como o sistema busca uma apolice?",
      queries: [ "Como o sistema busca uma apolice?" ], query_expansion: nil, multi_query: nil,
      metadata_filters: Documents::MetadataFilters.empty, metrics: {}, stage_failures: [], duration_ms: 10.0
    )
  end

  it "raises InvalidQuestionError for a blank question without touching retrieval" do
    unreachable_pipeline = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise "não deveria ser chamado" }
    end

    expect do
      Documents::QuestionAnsweringService.call(
        question: "   ",
        persist_enabled: false,
        retrieval_pipeline: unreachable_pipeline
      )
    end.to raise_error(Documents::QuestionAnsweringService::InvalidQuestionError)
  end

  it "runs the hallucination check when enabled and surfaces its result" do
    document = create(:document, title: "Manual de Teste", content: "Conteudo de teste.")
    chunk = document.document_chunks.create!(
      content: "O sistema busca uma apolice antes da averbacao.", position: 0, embedding: Array.new(1536, 0.01)
    )

    retrieval_result = build_retrieval_result(chunk)
    fake_retrieval_pipeline = Class.new do
      define_singleton_method(:call) { |**_kwargs| retrieval_result }
    end

    chat_result = Ai::ChatCompletionService::Result.new(
      content: "O sistema busca a apolice antes da averbacao [FONTE 1].", model: "fake-model",
      finish_reason: "stop", usage: { total_tokens: 15 }, prompt_tokens: 10, completion_tokens: 5,
      total_tokens: 15, duration_ms: 1.0
    )
    fake_chat_completion_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| chat_result }
    end

    hallucination_result = Documents::HallucinationCheckService::Result.new(
      verdicts: [], supported_count: 1, unsupported_count: 0, hallucination_rate: 0.0,
      model: "fake-model", duration_ms: 2.0
    )
    received_kwargs = nil
    fake_hallucination_service = Class.new do
      define_singleton_method(:call) do |**kwargs|
        received_kwargs = kwargs
        hallucination_result
      end
    end

    result = Documents::QuestionAnsweringService.call(
      question: "Como o sistema busca uma apolice?",
      persist_enabled: false,
      hallucination_check_enabled: true,
      retrieval_pipeline: fake_retrieval_pipeline,
      chat_completion_service: fake_chat_completion_service,
      hallucination_check_service: fake_hallucination_service
    )

    expect(result.hallucination_check).to eq(hallucination_result)
    expect(received_kwargs[:question]).to eq("Como o sistema busca uma apolice?")
    expect(received_kwargs[:answer]).to eq(chat_result.content)
  end

  it "wraps an unexpected error raised deep in the pipeline as a generic Error" do
    raising_pipeline = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise "falha de infraestrutura inesperada" }
    end

    expect do
      Documents::QuestionAnsweringService.call(
        question: "Como o sistema busca uma apolice?",
        persist_enabled: false,
        retrieval_pipeline: raising_pipeline
      )
    end.to raise_error(Documents::QuestionAnsweringService::Error) { |error|
      expect(error.message).to include("Não foi possível responder à pergunta")
      expect(error.message).to include("falha de infraestrutura inesperada")
    }
  end
end
