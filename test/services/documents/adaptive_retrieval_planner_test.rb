require "test_helper"

class Documents::AdaptiveRetrievalPlannerTest < ActiveSupport::TestCase
  test "short question gets the simple plan and skips expensive stages" do
    plan = Documents::AdaptiveRetrievalPlanner.call(question: "O que é apolice?")

    assert_equal :simple, plan.complexity
    assert_not plan.query_expansion_enabled
    assert_not plan.multi_query_enabled
    assert_not plan.cross_encoder_enabled
  end

  test "comparison keywords trigger the complex plan" do
    plan = Documents::AdaptiveRetrievalPlanner.call(
      question: "Compare o processo de busca de apolice com o de averbacao"
    )

    assert_equal :complex, plan.complexity
    assert plan.multi_query_enabled
    assert plan.cross_encoder_enabled
  end

  test "an explicit category from the query router overrides the heuristic" do
    plan = Documents::AdaptiveRetrievalPlanner.call(
      question: "O que é apolice?",
      category: "comparacao"
    )

    assert_equal :complex, plan.complexity
  end

  test "unknown category falls back to the standard plan" do
    plan = Documents::AdaptiveRetrievalPlanner.call(
      question: "Pergunta de tamanho médio sobre o processo de averbação",
      category: "algo_desconhecido"
    )

    assert_equal :standard, plan.complexity
  end

  test "raises for a blank question" do
    assert_raises(Documents::AdaptiveRetrievalPlanner::InvalidQuestionError) do
      Documents::AdaptiveRetrievalPlanner.call(question: "   ")
    end
  end
end
