require "test_helper"

class RagAnswerTest < ActiveSupport::TestCase
  def build_query
    RagQuery.create!(question: "Pergunta de teste", status: "completed")
  end

  test "requires an answer" do
    answer = RagAnswer.new(rag_query: build_query, answer: nil)

    assert_not answer.valid?
    assert_includes answer.errors.attribute_names, :answer
  end

  test "requires a rag_query" do
    answer = RagAnswer.new(answer: "Resposta de teste")

    assert_not answer.valid?
    assert_includes answer.errors.attribute_names, :rag_query
  end

  test "destroying the answer destroys its feedbacks" do
    answer = RagAnswer.create!(rag_query: build_query, answer: "Resposta de teste")
    feedback = RagFeedback.create!(rag_answer: answer, rating: "positive")

    answer.destroy!

    assert_not RagFeedback.exists?(feedback.id)
  end
end
