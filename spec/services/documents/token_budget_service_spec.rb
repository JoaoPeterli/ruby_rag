require "rails_helper"

RSpec.describe Documents::TokenBudgetService do
  it "splits the total budget between response, system prompt and context" do
    result = Documents::TokenBudgetService.call(
      total_budget: 4_000,
      response_reserve: 500,
      system_prompt_reserve: 200
    )

    expect(result.total_budget_tokens).to eq(4_000)
    expect(result.response_budget_tokens).to eq(500)
    expect(result.system_prompt_reserve_tokens).to eq(200)
    expect(result.context_budget_tokens).to eq(3_300)
    expect(result.context_budget_characters).to eq(13_200)
  end

  it "never lets the context budget go below the minimum floor" do
    result = Documents::TokenBudgetService.call(
      total_budget: 600,
      response_reserve: 500,
      system_prompt_reserve: 200
    )

    expect(result.context_budget_tokens).to eq(Documents::TokenBudgetService::MINIMUM_CONTEXT_BUDGET)
  end

  it "raises for a non-positive total budget" do
    expect do
      Documents::TokenBudgetService.call(total_budget: 0)
    end.to raise_error(Documents::TokenBudgetService::InvalidBudgetError)
  end
end
