require "rails_helper"

RSpec.describe Ai::CostCalculator do
  it "returns zero cost and priced false when no price is configured" do
    result = Ai::CostCalculator.call(
      model: "a-model-without-configured-pricing",
      prompt_tokens: 1_000,
      completion_tokens: 200
    )

    expect(result.total_cost_usd).to eq(0.0)
    expect(result.priced).to be(false)
    expect(result.total_tokens).to eq(1_200)
  end

  it "computes cost from ENV-configured pricing" do
    ENV["OPENAI_PRICE_TEST_MODEL_INPUT_PER_1M"] = "1.0"
    ENV["OPENAI_PRICE_TEST_MODEL_OUTPUT_PER_1M"] = "2.0"

    result = Ai::CostCalculator.call(
      model: "test-model",
      prompt_tokens: 1_000_000,
      completion_tokens: 500_000
    )

    expect(result.priced).to be(true)
    expect(result.prompt_cost_usd).to eq(1.0)
    expect(result.completion_cost_usd).to eq(1.0)
    expect(result.total_cost_usd).to eq(2.0)
  ensure
    ENV.delete("OPENAI_PRICE_TEST_MODEL_INPUT_PER_1M")
    ENV.delete("OPENAI_PRICE_TEST_MODEL_OUTPUT_PER_1M")
  end
end
