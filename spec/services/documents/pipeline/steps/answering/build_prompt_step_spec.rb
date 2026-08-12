require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::Answering::BuildPromptStep do
  def context_result_double_class
    @context_result_double_class ||= Struct.new(:sources, :context, keyword_init: true)
  end

  def build_context(prompt_builder:, effective_question: "pergunta efetiva", history: [])
    config = Documents::QuestionAnsweringService::Config.new(
      **Documents::QuestionAnsweringService::Config.members.index_with { nil }
    ).with(prompt_builder: prompt_builder)

    context = Documents::Pipeline::AnswerContext.new(
      question: "pergunta original", account_id: nil, conversation_history: history,
      config: config, on_delta: nil, started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
    )
    context.effective_question = effective_question
    context.context_result = context_result_double_class.new(sources: [], context: "contexto")
    context
  end

  def fake_builder(&on_call)
    canned = Documents::PromptBuilder::Result.new(
      messages: [ { role: "user", content: "oi" } ], system_prompt: "sistema",
      user_prompt: "usuario", context_included: true, sources_count: 0
    )

    Class.new do
      define_singleton_method(:call) do |**kwargs|
        on_call.call(kwargs) if on_call
        canned
      end
    end
  end

  it "builds the prompt from the effective question, context_result and conversation history" do
    history = [ { role: "user", content: "oi" } ]
    received = nil

    context = build_context(
      prompt_builder: fake_builder { |kwargs| received = kwargs },
      effective_question: "qual o prazo?",
      history: history
    )
    Documents::Pipeline::Steps::Answering::BuildPromptStep.call(context: context)

    expect(received[:question]).to eq("qual o prazo?")
    expect(received[:context_result]).to equal(context.context_result)
    expect(received[:conversation_history]).to eq(history)
    expect(context.prompt.messages).to eq([ { role: "user", content: "oi" } ])
  end

  it "wraps prompt builder failures as PromptBuildError" do
    raising_builder = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Documents::PromptBuilder::Error, "sem contexto" }
    end

    context = build_context(prompt_builder: raising_builder)

    expect do
      Documents::Pipeline::Steps::Answering::BuildPromptStep.call(context: context)
    end.to raise_error(Documents::QuestionAnsweringService::PromptBuildError)
  end

  it "does nothing when context.result is already set" do
    unreachable = Class.new { define_singleton_method(:call) { |**_k| raise "não deveria ser chamado" } }
    context = build_context(prompt_builder: unreachable)
    context.result = :already_resolved

    Documents::Pipeline::Steps::Answering::BuildPromptStep.call(context: context)

    expect(context.prompt).to be_nil
  end
end
