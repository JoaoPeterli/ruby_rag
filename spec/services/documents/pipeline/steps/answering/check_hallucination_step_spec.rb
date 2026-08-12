require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::Answering::CheckHallucinationStep do
  def chat_result_double_class
    @chat_result_double_class ||= Struct.new(:content, keyword_init: true)
  end

  def context_result_double_class
    @context_result_double_class ||= Struct.new(:context, keyword_init: true)
  end

  def build_context(enabled:, hallucination_check_service:)
    config = Documents::QuestionAnsweringService::Config.new(
      **Documents::QuestionAnsweringService::Config.members.index_with { nil }
    ).with(hallucination_check_enabled: enabled, hallucination_check_service: hallucination_check_service)

    context = Documents::Pipeline::AnswerContext.new(
      question: "pergunta original", account_id: nil, conversation_history: [],
      config: config, on_delta: nil, started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
    )
    context.effective_question = "pergunta reescrita"
    context.chat_result = chat_result_double_class.new(content: "resposta gerada")
    context.context_result = context_result_double_class.new(context: "contexto recuperado")
    context
  end

  def unreachable
    Class.new { define_singleton_method(:call) { |**_k| raise "não deveria ser chamado" } }
  end

  it "calls the hallucination service with the effective question, answer and retrieved context when enabled" do
    received = nil
    service = Class.new do
      define_singleton_method(:call) do |**kwargs|
        received = kwargs
        Documents::HallucinationCheckService::Result.new(
          verdicts: [], supported_count: 0, unsupported_count: 0, hallucination_rate: 0.0,
          model: "m", duration_ms: 1.0
        )
      end
    end

    context = build_context(enabled: true, hallucination_check_service: service)
    Documents::Pipeline::Steps::Answering::CheckHallucinationStep.call(context: context)

    expect(received[:question]).to eq("pergunta reescrita")
    expect(received[:answer]).to eq("resposta gerada")
    expect(received[:context]).to eq("contexto recuperado")
    expect(context.hallucination_result.hallucination_rate).to eq(0.0)
  end

  it "does nothing when hallucination_check_enabled is false" do
    context = build_context(enabled: false, hallucination_check_service: unreachable)

    Documents::Pipeline::Steps::Answering::CheckHallucinationStep.call(context: context)

    expect(context.hallucination_result).to be_nil
  end

  it "swallows HallucinationCheckService::Error and leaves hallucination_result nil" do
    raising_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| raise Documents::HallucinationCheckService::Error, "falhou" }
    end

    context = build_context(enabled: true, hallucination_check_service: raising_service)

    expect do
      Documents::Pipeline::Steps::Answering::CheckHallucinationStep.call(context: context)
    end.not_to raise_error
    expect(context.hallucination_result).to be_nil
  end

  it "does nothing when context.result is already set" do
    context = build_context(enabled: true, hallucination_check_service: unreachable)
    context.result = :already_resolved

    Documents::Pipeline::Steps::Answering::CheckHallucinationStep.call(context: context)

    expect(context.hallucination_result).to be_nil
  end
end
