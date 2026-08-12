require "rails_helper"

RSpec.describe RagAnswer do
  it "requires an answer" do
    answer = build(:rag_answer, answer: nil)

    expect(answer).not_to be_valid
    expect(answer.errors.attribute_names).to include(:answer)
  end

  it "requires a rag_query" do
    answer = RagAnswer.new(answer: "Resposta de teste")

    expect(answer).not_to be_valid
    expect(answer.errors.attribute_names).to include(:rag_query)
  end

  it "destroys its feedbacks when destroyed" do
    answer = create(:rag_answer)
    feedback = create(:rag_feedback, rag_answer: answer)

    answer.destroy!

    expect(RagFeedback.exists?(feedback.id)).to be(false)
  end
end
