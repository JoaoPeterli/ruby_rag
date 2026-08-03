require "test_helper"

class RagQueryTest < ActiveSupport::TestCase
  test "requires a question and a valid status" do
    query = RagQuery.new(question: nil, status: "unknown")

    assert_not query.valid?
    assert_includes query.errors.attribute_names, :question
    assert_includes query.errors.attribute_names, :status
  end

  test "accepts every declared status" do
    RagQuery::STATUSES.each do |status|
      query = RagQuery.new(question: "Pergunta de teste", status: status)

      assert query.valid?, "esperava #{status} ser válido"
    end
  end

  test "has_one rag_answer and has_many rag_retrieval_results" do
    query = RagQuery.create!(question: "Pergunta de teste", status: "completed")
    answer = RagAnswer.create!(rag_query: query, answer: "Resposta de teste")

    assert_equal answer, query.reload.rag_answer
    assert_equal [], query.rag_retrieval_results
  end
end
