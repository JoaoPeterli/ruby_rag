require "test_helper"

class RagFeedbackTest < ActiveSupport::TestCase
  def build_answer
    query = RagQuery.create!(question: "Pergunta de teste", status: "completed")
    RagAnswer.create!(rag_query: query, answer: "Resposta de teste")
  end

  test "only accepts positive or negative ratings" do
    valid = RagFeedback.new(rag_answer: build_answer, rating: "positive")
    invalid = RagFeedback.new(rag_answer: build_answer, rating: "meh")

    assert valid.valid?
    assert_not invalid.valid?
    assert_includes invalid.errors.attribute_names, :rating
  end

  test "reason is optional" do
    feedback = RagFeedback.new(rag_answer: build_answer, rating: "negative", reason: nil)

    assert feedback.valid?
  end
end
