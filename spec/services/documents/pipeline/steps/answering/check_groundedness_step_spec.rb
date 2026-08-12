require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::Answering::CheckGroundednessStep do
  def chat_result_double_class
    @chat_result_double_class ||= Struct.new(:content, keyword_init: true)
  end

  def citation_result_double_class
    @citation_result_double_class ||= Struct.new(:citation_count, keyword_init: true)
  end

  def build_context(enabled:, groundedness_check_service:, citation_result: nil)
    config = Documents::QuestionAnsweringService::Config.new(
      **Documents::QuestionAnsweringService::Config.members.index_with { nil }
    ).with(groundedness_check_enabled: enabled, groundedness_check_service: groundedness_check_service)

    context = Documents::Pipeline::AnswerContext.new(
      question: "pergunta", account_id: nil, conversation_history: [],
      config: config, on_delta: nil, started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
    )
    context.chat_result = chat_result_double_class.new(content: "resposta [FONTE 1]")
    context.citation_result = citation_result
    context
  end

  def unreachable
    Class.new { define_singleton_method(:call) { |**_k| raise "não deveria ser chamado" } }
  end

  it "calls the groundedness service with the answer and citation_count when enabled" do
    received = nil
    service = Class.new do
      define_singleton_method(:call) { |**kwargs| received = kwargs; Documents::GroundednessCheckService::Result.new(grounded: true, refused: false, citation_count: 1, reason: nil) }
    end

    context = build_context(enabled: true, groundedness_check_service: service, citation_result: citation_result_double_class.new(citation_count: 3))
    Documents::Pipeline::Steps::Answering::CheckGroundednessStep.call(context: context)

    expect(received[:answer]).to eq("resposta [FONTE 1]")
    expect(received[:citation_count]).to eq(3)
    expect(context.groundedness_result.grounded).to be_truthy
  end

  it "defaults citation_count to zero when there is no citation_result" do
    received = nil
    service = Class.new do
      define_singleton_method(:call) { |**kwargs| received = kwargs; Documents::GroundednessCheckService::Result.new(grounded: false, refused: false, citation_count: 0, reason: "x") }
    end

    context = build_context(enabled: true, groundedness_check_service: service, citation_result: nil)
    Documents::Pipeline::Steps::Answering::CheckGroundednessStep.call(context: context)

    expect(received[:citation_count]).to eq(0)
  end

  it "does nothing when groundedness_check_enabled is false" do
    context = build_context(enabled: false, groundedness_check_service: unreachable)

    Documents::Pipeline::Steps::Answering::CheckGroundednessStep.call(context: context)

    expect(context.groundedness_result).to be_nil
  end

  it "swallows GroundednessCheckService::Error and leaves groundedness_result nil" do
    raising_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Documents::GroundednessCheckService::Error, "falhou" }
    end

    context = build_context(enabled: true, groundedness_check_service: raising_service)

    expect do
      Documents::Pipeline::Steps::Answering::CheckGroundednessStep.call(context: context)
    end.not_to raise_error
    expect(context.groundedness_result).to be_nil
  end

  it "does nothing when context.result is already set" do
    context = build_context(enabled: true, groundedness_check_service: unreachable)
    context.result = :already_resolved

    Documents::Pipeline::Steps::Answering::CheckGroundednessStep.call(context: context)

    expect(context.groundedness_result).to be_nil
  end
end
