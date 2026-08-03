require "test_helper"

class Ai::TokenEstimatorTest < ActiveSupport::TestCase
  test "estimate divides characters by the chars-per-token ratio" do
    assert_equal 25, Ai::TokenEstimator.estimate("a" * 100)
  end

  test "estimate rounds up" do
    assert_equal 1, Ai::TokenEstimator.estimate("ab")
  end

  test "estimate of blank text is zero" do
    assert_equal 0, Ai::TokenEstimator.estimate("")
    assert_equal 0, Ai::TokenEstimator.estimate(nil)
  end

  test "characters_for is the inverse of estimate" do
    assert_equal 400, Ai::TokenEstimator.characters_for(100)
  end
end
