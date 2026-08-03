require "test_helper"

class RagEvalCaseTest < ActiveSupport::TestCase
  test "requires a question" do
    eval_case = RagEvalCase.new(question: nil)

    assert_not eval_case.valid?
    assert_includes eval_case.errors.attribute_names, :question
  end

  test "expects_answer? reflects whether expected_answer is present" do
    with_answer = RagEvalCase.new(question: "P", expected_answer: "Resposta esperada")
    without_answer = RagEvalCase.new(question: "P", expected_answer: nil)

    assert with_answer.expects_answer?
    assert_not without_answer.expects_answer?
  end

  test "active scope only returns active cases" do
    active_case = RagEvalCase.create!(question: "Ativo", active: true)
    inactive_case = RagEvalCase.create!(question: "Inativo", active: false)

    result = RagEvalCase.active

    assert_includes result, active_case
    assert_not_includes result, inactive_case
  end

  test "by_category scope filters by category" do
    factual = RagEvalCase.create!(question: "P1", category: "factual")
    RagEvalCase.create!(question: "P2", category: "resumo")

    assert_equal [ factual ], RagEvalCase.by_category("factual").to_a
  end
end
