require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::Answering::SemanticCacheLookupStep do
  def cache_entry_double_class
    @cache_entry_double_class ||= Struct.new(:answer, :model, :confidence_score, :confidence_level, keyword_init: true)
  end

  def build_context(config:)
    context = Documents::Pipeline::AnswerContext.new(
      question: "Qual o prazo da apólice?",
      account_id: nil,
      conversation_history: [],
      config: config,
      on_delta: nil,
      started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
    )
    context.normalized_question = "Qual o prazo da apólice?"
    context.effective_question = "Qual o prazo da apólice?"
    context
  end

  def unreachable_service
    Class.new { define_singleton_method(:call) { |**_kwargs| raise "não deveria ser chamado" } }
  end

  it "does nothing when the semantic cache is disabled" do
    context = build_context(
      config: base_config(semantic_cache_enabled: false, embedding_service: unreachable_service, semantic_cache_lookup_service: unreachable_service)
    )

    Documents::Pipeline::Steps::Answering::SemanticCacheLookupStep.call(context: context)

    expect(context.question_embedding).to be_nil
    expect(context.result).to be_nil
    expect(context.cache_hit).to be_nil
  end

  it "sets cache_hit and a cache Result when a hit is found" do
    entry = cache_entry_double_class.new(answer: "Resposta em cache.", model: "fake-model", confidence_score: 0.9, confidence_level: "high")
    hit = Documents::SemanticCacheLookupService::Result.new(entry: entry, similarity: 0.98)

    embedding_service = Class.new { define_singleton_method(:call) { |**_kwargs| [ Array.new(1536, 0.01) ] } }
    lookup_service = Class.new { define_singleton_method(:call) { |**_kwargs| hit } }

    context = build_context(
      config: base_config(semantic_cache_enabled: true, embedding_service: embedding_service, semantic_cache_lookup_service: lookup_service)
    )

    Documents::Pipeline::Steps::Answering::SemanticCacheLookupStep.call(context: context)

    expect(context.cache_hit).to eq(hit)
    expect(context.result.cache_hit).to be_truthy
    expect(context.result.answer).to eq("Resposta em cache.")
    expect(context.result.cache_similarity).to be_within(0.0001).of(0.98)
  end

  it "leaves result untouched when there is no cache hit" do
    embedding_service = Class.new { define_singleton_method(:call) { |**_kwargs| [ Array.new(1536, 0.01) ] } }
    lookup_service = Class.new { define_singleton_method(:call) { |**_kwargs| nil } }

    context = build_context(
      config: base_config(semantic_cache_enabled: true, embedding_service: embedding_service, semantic_cache_lookup_service: lookup_service)
    )

    Documents::Pipeline::Steps::Answering::SemanticCacheLookupStep.call(context: context)

    expect(context.result).to be_nil
    expect(context.cache_hit).to be_nil
    expect(context.question_embedding).to eq(Array.new(1536, 0.01))
  end

  it "swallows an embedding failure, leaving question_embedding nil and skipping the lookup" do
    raising_embedding_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Ai::EmbeddingService::Error, "falha" }
    end

    context = build_context(
      config: base_config(semantic_cache_enabled: true, embedding_service: raising_embedding_service, semantic_cache_lookup_service: unreachable_service)
    )

    Documents::Pipeline::Steps::Answering::SemanticCacheLookupStep.call(context: context)

    expect(context.question_embedding).to be_nil
    expect(context.result).to be_nil
  end

  it "swallows a lookup failure" do
    embedding_service = Class.new { define_singleton_method(:call) { |**_kwargs| [ Array.new(1536, 0.01) ] } }
    raising_lookup_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Documents::SemanticCacheLookupService::Error, "falha" }
    end

    context = build_context(
      config: base_config(semantic_cache_enabled: true, embedding_service: embedding_service, semantic_cache_lookup_service: raising_lookup_service)
    )

    Documents::Pipeline::Steps::Answering::SemanticCacheLookupStep.call(context: context)

    expect(context.result).to be_nil
    expect(context.cache_hit).to be_nil
  end
end
