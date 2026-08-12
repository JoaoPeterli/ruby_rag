require "rails_helper"

RSpec.describe Documents::Pipeline::Steps::Answering::ValidateQuestionStep do
  def build_context(question:)
    Documents::Pipeline::AnswerContext.new(
      question: question,
      account_id: nil,
      conversation_history: [],
      config: nil,
      on_delta: nil,
      started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
    )
  end

  it "strips the question and stores it as normalized_question" do
    context = build_context(question: "  Qual o prazo?  ")

    Documents::Pipeline::Steps::Answering::ValidateQuestionStep.call(context: context)

    expect(context.normalized_question).to eq("Qual o prazo?")
  end

  it "raises for a blank question" do
    context = build_context(question: "   ")

    expect do
      Documents::Pipeline::Steps::Answering::ValidateQuestionStep.call(context: context)
    end.to raise_error(Documents::QuestionAnsweringService::InvalidQuestionError)
  end

  it "raises for a non-string question" do
    context = build_context(question: nil)

    expect do
      Documents::Pipeline::Steps::Answering::ValidateQuestionStep.call(context: context)
    end.to raise_error(Documents::QuestionAnsweringService::InvalidQuestionError)
  end
end
