require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::Answering::BuildCitationsStep do
  def chat_result_double_class
    @chat_result_double_class ||= Struct.new(:content, keyword_init: true)
  end

  def context_result_double_class
    @context_result_double_class ||= Struct.new(:sources, keyword_init: true)
  end

  def build_context(enabled:, citation_engine:)
    config = Documents::QuestionAnsweringService::Config.new(
      **Documents::QuestionAnsweringService::Config.members.index_with { nil }
    ).with(citation_engine_enabled: enabled, citation_engine: citation_engine)

    context = Documents::Pipeline::AnswerContext.new(
      question: "pergunta", account_id: nil, conversation_history: [],
      config: config, on_delta: nil, started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
    )
    context.chat_result = chat_result_double_class.new(content: "resposta [FONTE 1]")
    context.context_result = context_result_double_class.new(sources: [ { source_number: 1 } ])
    context
  end

  def unreachable
    Class.new { define_singleton_method(:call) { |**_k| raise "não deveria ser chamado" } }
  end

  it "calls the citation engine with the answer and sources when enabled" do
    received = nil
    canned = Documents::CitationEngine::Result.new(
      answer: "resposta [FONTE 1]", citations: [], cited_source_numbers: [], uncited_source_numbers: [],
      citation_count: 1, source_count: 1, citation_coverage: 1.0, duration_ms: 1.0
    )
    citation_engine = Class.new do
      define_singleton_method(:call) do |**kwargs|
        received = kwargs
        canned
      end
    end

    context = build_context(enabled: true, citation_engine: citation_engine)
    Documents::Pipeline::Steps::Answering::BuildCitationsStep.call(context: context)

    expect(received[:answer]).to eq("resposta [FONTE 1]")
    expect(received[:sources]).to eq([ { source_number: 1 } ])
    expect(context.citation_result).to equal(canned)
  end

  it "does nothing when citation_engine_enabled is false" do
    context = build_context(enabled: false, citation_engine: unreachable)

    Documents::Pipeline::Steps::Answering::BuildCitationsStep.call(context: context)

    expect(context.citation_result).to be_nil
  end

  it "swallows CitationEngine::Service::Error and leaves citation_result nil" do
    raising_engine = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Documents::CitationEngine::Service::Error, "falhou" }
    end

    context = build_context(enabled: true, citation_engine: raising_engine)

    expect do
      Documents::Pipeline::Steps::Answering::BuildCitationsStep.call(context: context)
    end.not_to raise_error
    expect(context.citation_result).to be_nil
  end

  it "does nothing when context.result is already set" do
    context = build_context(enabled: true, citation_engine: unreachable)
    context.result = :already_resolved

    Documents::Pipeline::Steps::Answering::BuildCitationsStep.call(context: context)

    expect(context.citation_result).to be_nil
  end
end
