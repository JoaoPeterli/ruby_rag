require "test_helper"

class Ai::CostCalculatorTest < ActiveSupport::TestCase
  test "returns zero cost and priced false when no price is configured" do
    result = Ai::CostCalculator.call(
      model: "a-model-without-configured-pricing",
      prompt_tokens: 1_000,
      completion_tokens: 200
    )

    assert_equal 0.0, result.total_cost_usd
    assert_not result.priced
    assert_equal 1_200, result.total_tokens
  end

  test "computes cost from ENV-configured pricing" do
    ENV["OPENAI_PRICE_TEST_MODEL_INPUT_PER_1M"] = "1.0"
    ENV["OPENAI_PRICE_TEST_MODEL_OUTPUT_PER_1M"] = "2.0"

    result = Ai::CostCalculator.call(
      model: "test-model",
      prompt_tokens: 1_000_000,
      completion_tokens: 500_000
    )

    assert result.priced
    assert_equal 1.0, result.prompt_cost_usd
    assert_equal 1.0, result.completion_cost_usd
    assert_equal 2.0, result.total_cost_usd
  ensure
    ENV.delete("OPENAI_PRICE_TEST_MODEL_INPUT_PER_1M")
    ENV.delete("OPENAI_PRICE_TEST_MODEL_OUTPUT_PER_1M")
  end
end
