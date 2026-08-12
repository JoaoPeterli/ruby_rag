require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::Answering::PersistStep do
  def rag_query_double_class
    @rag_query_double_class ||= Struct.new(:id, :rag_answer, keyword_init: true)
  end

  def rag_answer_double_class
    @rag_answer_double_class ||= Struct.new(:id, keyword_init: true)
  end

  def build_context(persist_enabled:, persistence_service:, result: sample_result)
    config = Documents::QuestionAnsweringService::Config.new(
      **Documents::QuestionAnsweringService::Config.members.index_with { nil }
    ).with(persist_enabled: persist_enabled, persistence_service: persistence_service)

    context = Documents::Pipeline::AnswerContext.new(
      question: "pergunta", account_id: 7, conversation_history: [],
      config: config, on_delta: nil, started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
    )
    context.retrieval_result = :retrieval
    context.result = result
    context
  end

  def sample_result
    Documents::QuestionAnsweringService::Result.new(
      **Documents::QuestionAnsweringService::Result.members.index_with { nil }
    ).with(answer: "resposta", rag_query_id: nil, rag_answer_id: nil)
  end

  def unreachable
    Class.new { define_singleton_method(:call) { |**_k| raise "não deveria ser chamado" } }
  end

  it "persists the result and stamps rag_query_id/rag_answer_id" do
    received = nil
    query_class = rag_query_double_class
    answer_class = rag_answer_double_class
    service = Class.new do
      define_singleton_method(:call) do |**kwargs|
        received = kwargs
        query_class.new(id: 42, rag_answer: answer_class.new(id: 99))
      end
    end

    context = build_context(persist_enabled: true, persistence_service: service)
    Documents::Pipeline::Steps::Answering::PersistStep.call(context: context)

    expect(received[:retrieval_result]).to eq(:retrieval)
    expect(received[:account_id]).to eq(7)
    expect(received[:qa_result].answer).to eq("resposta")
    expect(context.result.rag_query_id).to eq(42)
    expect(context.result.rag_answer_id).to eq(99)
    expect(context.result.answer).to eq("resposta")
  end

  it "leaves rag_answer_id nil when the persisted query has no rag_answer yet" do
    query_class = rag_query_double_class
    service = Class.new do
      define_singleton_method(:call) { |**_kwargs| query_class.new(id: 42, rag_answer: nil) }
    end

    context = build_context(persist_enabled: true, persistence_service: service)
    Documents::Pipeline::Steps::Answering::PersistStep.call(context: context)

    expect(context.result.rag_query_id).to eq(42)
    expect(context.result.rag_answer_id).to be_nil
  end

  it "does nothing when persist_enabled is false" do
    context = build_context(persist_enabled: false, persistence_service: unreachable)

    Documents::Pipeline::Steps::Answering::PersistStep.call(context: context)

    expect(context.result.rag_query_id).to be_nil
  end

  it "runs even when context.result was already set by an earlier shortcut" do
    query_class = rag_query_double_class
    service = Class.new do
      define_singleton_method(:call) { |**_kwargs| query_class.new(id: 5, rag_answer: nil) }
    end

    cached_result = sample_result.with(cache_hit: true, answer: "resposta em cache")
    context = build_context(persist_enabled: true, persistence_service: service, result: cached_result)

    Documents::Pipeline::Steps::Answering::PersistStep.call(context: context)

    expect(context.result.rag_query_id).to eq(5)
    expect(context.result.cache_hit).to be_truthy
  end

  it "swallows RagPersistenceService::Error and leaves the result unchanged" do
    raising_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Documents::RagPersistenceService::Error, "falhou" }
    end

    context = build_context(persist_enabled: true, persistence_service: raising_service)

    expect do
      Documents::Pipeline::Steps::Answering::PersistStep.call(context: context)
    end.not_to raise_error
    expect(context.result.rag_query_id).to be_nil
  end
end
