require "test_helper"

class Documents::TokenBudgetServiceTest < ActiveSupport::TestCase
  test "splits the total budget between response, system prompt and context" do
    result = Documents::TokenBudgetService.call(
      total_budget: 4_000,
      response_reserve: 500,
      system_prompt_reserve: 200
    )

    assert_equal 4_000, result.total_budget_tokens
    assert_equal 500, result.response_budget_tokens
    assert_equal 200, result.system_prompt_reserve_tokens
    assert_equal 3_300, result.context_budget_tokens
    assert_equal 13_200, result.context_budget_characters
  end

  test "never lets the context budget go below the minimum floor" do
    result = Documents::TokenBudgetService.call(
      total_budget: 600,
      response_reserve: 500,
      system_prompt_reserve: 200
    )

    assert_equal Documents::TokenBudgetService::MINIMUM_CONTEXT_BUDGET,
                 result.context_budget_tokens
  end

  test "raises for a non-positive total budget" do
    assert_raises(Documents::TokenBudgetService::InvalidBudgetError) do
      Documents::TokenBudgetService.call(total_budget: 0)
    end
  end
end
