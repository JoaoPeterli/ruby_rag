require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::Answering::ResolveEffectiveQuestionStep do
  def build_context(config:, conversation_history: [])
    context = Documents::Pipeline::AnswerContext.new(
      question: "Qual o prazo da apólice?",
      account_id: nil,
      conversation_history: conversation_history,
      config: config,
      on_delta: nil,
      started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
    )
    context.normalized_question = "Qual o prazo da apólice?"
    context
  end

  def rewrite_result(rewritten_question:)
    Documents::QueryRewriteService::Result.new(
      original_question: "Qual o prazo da apólice?",
      rewritten_question: rewritten_question,
      rewritten: true,
      model: "fake-model",
      duration_ms: 1.0
    )
  end

  it "uses normalized_question when query rewrite is disabled" do
    context = build_context(config: base_config(query_rewrite_enabled: false), conversation_history: [ { role: "user", content: "oi" } ])

    Documents::Pipeline::Steps::Answering::ResolveEffectiveQuestionStep.call(context: context)

    expect(context.query_rewrite_result).to be_nil
    expect(context.effective_question).to eq("Qual o prazo da apólice?")
  end

  it "skips rewriting when there is no conversation history even if enabled" do
    fake_service = Class.new { define_singleton_method(:call) { |**_kwargs| raise "não deveria ser chamado" } }
    context = build_context(config: base_config(query_rewrite_enabled: true, query_rewrite_service: fake_service), conversation_history: [])

    Documents::Pipeline::Steps::Answering::ResolveEffectiveQuestionStep.call(context: context)

    expect(context.effective_question).to eq("Qual o prazo da apólice?")
  end

  it "uses the rewritten question when rewrite is enabled with history" do
    canned_result = rewrite_result(rewritten_question: "Qual o prazo de vigência da apólice de seguro?")
    fake_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| canned_result }
    end

    context = build_context(
      config: base_config(query_rewrite_enabled: true, query_rewrite_service: fake_service),
      conversation_history: [ { role: "user", content: "e a apólice?" } ]
    )

    Documents::Pipeline::Steps::Answering::ResolveEffectiveQuestionStep.call(context: context)

    expect(context.effective_question).to eq("Qual o prazo de vigência da apólice de seguro?")
    expect(context.query_rewrite_result.rewritten_question).to eq("Qual o prazo de vigência da apólice de seguro?")
  end

  it "falls back to normalized_question when the rewrite service raises" do
    raising_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Documents::QueryRewriteService::Error, "falha" }
    end

    context = build_context(
      config: base_config(query_rewrite_enabled: true, query_rewrite_service: raising_service),
      conversation_history: [ { role: "user", content: "e a apólice?" } ]
    )

    Documents::Pipeline::Steps::Answering::ResolveEffectiveQuestionStep.call(context: context)

    expect(context.query_rewrite_result).to be_nil
    expect(context.effective_question).to eq("Qual o prazo da apólice?")
  end
end
