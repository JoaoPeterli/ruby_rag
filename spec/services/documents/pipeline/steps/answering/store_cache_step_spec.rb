require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::Answering::StoreCacheStep do
  def build_context(config:, cache_hit: nil, question_embedding: nil, result: :final_answer, account_id: nil)
    context = Documents::Pipeline::AnswerContext.new(
      question: "Qual o prazo da apólice?",
      account_id: account_id,
      conversation_history: [],
      config: config,
      on_delta: nil,
      started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
    )
    context.effective_question = "Qual o prazo da apólice?"
    context.cache_hit = cache_hit
    context.question_embedding = question_embedding
    context.result = result
    context
  end

  def unreachable_service
    Class.new { define_singleton_method(:call) { |**_kwargs| raise "não deveria ser chamado" } }
  end

  it "does not store again when the result came from a cache hit" do
    context = build_context(
      config: base_config(semantic_cache_enabled: true, semantic_cache_store_service: unreachable_service),
      cache_hit: :some_hit,
      question_embedding: Array.new(1536, 0.01)
    )

    expect(Documents::Pipeline::Steps::Answering::StoreCacheStep.call(context: context)).to be_nil
  end

  it "does not store when the semantic cache is disabled" do
    context = build_context(
      config: base_config(semantic_cache_enabled: false, semantic_cache_store_service: unreachable_service),
      question_embedding: Array.new(1536, 0.01)
    )

    expect(Documents::Pipeline::Steps::Answering::StoreCacheStep.call(context: context)).to be_nil
  end

  it "does not store when there is no question_embedding" do
    context = build_context(
      config: base_config(semantic_cache_enabled: true, semantic_cache_store_service: unreachable_service),
      question_embedding: nil
    )

    expect(Documents::Pipeline::Steps::Answering::StoreCacheStep.call(context: context)).to be_nil
  end

  it "stores the answer with the expected arguments when eligible" do
    received = nil
    store_service = Class.new do
      define_singleton_method(:call) { |**kwargs| received = kwargs }
    end

    embedding = Array.new(1536, 0.02)
    context = build_context(
      config: base_config(semantic_cache_enabled: true, semantic_cache_ttl: 3600, semantic_cache_store_service: store_service),
      question_embedding: embedding,
      result: :final_answer,
      account_id: 42
    )

    Documents::Pipeline::Steps::Answering::StoreCacheStep.call(context: context)

    expect(received[:question]).to eq("Qual o prazo da apólice?")
    expect(received[:question_embedding]).to eq(embedding)
    expect(received[:qa_result]).to eq(:final_answer)
    expect(received[:ttl]).to eq(3600)
    expect(received[:account_id]).to eq(42)
  end

  it "swallows a store failure without raising" do
    raising_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Documents::SemanticCacheStoreService::Error, "falha" }
    end

    context = build_context(
      config: base_config(semantic_cache_enabled: true, semantic_cache_store_service: raising_service),
      question_embedding: Array.new(1536, 0.01)
    )

    expect(Documents::Pipeline::Steps::Answering::StoreCacheStep.call(context: context)).to be_nil
  end
end
