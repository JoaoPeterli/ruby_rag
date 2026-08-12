require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::Answering::CalculateConfidenceStep do
  def build_context(enabled:, confidence_score_service:)
    config = Documents::QuestionAnsweringService::Config.new(
      **Documents::QuestionAnsweringService::Config.members.index_with { nil }
    ).with(confidence_score_enabled: enabled, confidence_score_service: confidence_score_service)

    context = Documents::Pipeline::AnswerContext.new(
      question: "pergunta", account_id: nil, conversation_history: [],
      config: config, on_delta: nil, started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
    )
    context.retrieval_result = :retrieval
    context.citation_result = :citation
    context.groundedness_result = :groundedness
    context.hallucination_result = :hallucination
    context
  end

  def unreachable
    Class.new { define_singleton_method(:call) { |**_k| raise "não deveria ser chamado" } }
  end

  it "combines every signal via the confidence score service when enabled" do
    received = nil
    service = Class.new do
      define_singleton_method(:call) do |**kwargs|
        received = kwargs
        Documents::ConfidenceScoreService::Result.new(score: 0.9, level: :high, components: {})
      end
    end

    context = build_context(enabled: true, confidence_score_service: service)
    Documents::Pipeline::Steps::Answering::CalculateConfidenceStep.call(context: context)

    expect(received[:retrieval_result]).to eq(:retrieval)
    expect(received[:citation_result]).to eq(:citation)
    expect(received[:groundedness_result]).to eq(:groundedness)
    expect(received[:hallucination_result]).to eq(:hallucination)
    expect(context.confidence_result.level).to eq(:high)
  end

  it "does nothing when confidence_score_enabled is false" do
    context = build_context(enabled: false, confidence_score_service: unreachable)

    Documents::Pipeline::Steps::Answering::CalculateConfidenceStep.call(context: context)

    expect(context.confidence_result).to be_nil
  end

  it "swallows ConfidenceScoreService::Error and leaves confidence_result nil" do
    raising_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Documents::ConfidenceScoreService::Error, "falhou" }
    end

    context = build_context(enabled: true, confidence_score_service: raising_service)

    expect do
      Documents::Pipeline::Steps::Answering::CalculateConfidenceStep.call(context: context)
    end.not_to raise_error
    expect(context.confidence_result).to be_nil
  end

  it "does nothing when context.result is already set" do
    context = build_context(enabled: true, confidence_score_service: unreachable)
    context.result = :already_resolved

    Documents::Pipeline::Steps::Answering::CalculateConfidenceStep.call(context: context)

    expect(context.confidence_result).to be_nil
  end
end
