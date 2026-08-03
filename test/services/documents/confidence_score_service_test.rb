require "test_helper"

class Documents::ConfidenceScoreServiceTest < ActiveSupport::TestCase
  FakeSearchResult = Struct.new(:combined_score, :rerank_score)
  FakeCrossEncoder = Struct.new(:average_score)
  FakeRetrievalResult = Struct.new(:results, :cross_encoder)
  FakeCitationResult = Struct.new(:citation_coverage)
  FakeGroundednessResult = Struct.new(:grounded, :refused)
  FakeHallucinationResult = Struct.new(:hallucination_rate)

  test "combines every available signal into a single score" do
    retrieval_result = FakeRetrievalResult.new(
      [ FakeSearchResult.new(0.9, nil), FakeSearchResult.new(0.7, nil) ],
      FakeCrossEncoder.new(0.8)
    )

    result = Documents::ConfidenceScoreService.call(
      retrieval_result: retrieval_result,
      citation_result: FakeCitationResult.new(0.5),
      groundedness_result: FakeGroundednessResult.new(true, false),
      hallucination_result: FakeHallucinationResult.new(0.0)
    )

    assert_includes 0.0..1.0, result.score
    assert_equal 5, result.components.size
    assert_equal :high, result.level
  end

  test "refused answers get partial groundedness credit" do
    retrieval_result = FakeRetrievalResult.new([], nil)

    refused = Documents::ConfidenceScoreService.call(
      retrieval_result: retrieval_result,
      groundedness_result: FakeGroundednessResult.new(true, true)
    )

    ungrounded = Documents::ConfidenceScoreService.call(
      retrieval_result: retrieval_result,
      groundedness_result: FakeGroundednessResult.new(false, false)
    )

    assert refused.score > ungrounded.score
  end

  test "missing signals are simply excluded, not treated as zero" do
    retrieval_result = FakeRetrievalResult.new([], nil)

    result = Documents::ConfidenceScoreService.call(
      retrieval_result: retrieval_result,
      groundedness_result: FakeGroundednessResult.new(true, false)
    )

    assert_equal 1, result.components.size
    assert_equal 1.0, result.score
  end

  test "raises when there is no usable signal at all" do
    retrieval_result = FakeRetrievalResult.new([], nil)

    assert_raises(Documents::ConfidenceScoreService::InvalidComponentsError) do
      Documents::ConfidenceScoreService.call(retrieval_result: retrieval_result)
    end
  end
end
