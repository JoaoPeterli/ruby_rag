require "rails_helper"

RSpec.describe Documents::ConfidenceScoreService do
  def fake_search_result_class
    @fake_search_result_class ||= Struct.new(:combined_score, :rerank_score)
  end

  def fake_cross_encoder_class
    @fake_cross_encoder_class ||= Struct.new(:average_score)
  end

  def fake_retrieval_result_class
    @fake_retrieval_result_class ||= Struct.new(:results, :cross_encoder)
  end

  def fake_citation_result_class
    @fake_citation_result_class ||= Struct.new(:citation_coverage)
  end

  def fake_groundedness_result_class
    @fake_groundedness_result_class ||= Struct.new(:grounded, :refused)
  end

  def fake_hallucination_result_class
    @fake_hallucination_result_class ||= Struct.new(:hallucination_rate)
  end

  it "combines every available signal into a single score" do
    retrieval_result = fake_retrieval_result_class.new(
      [ fake_search_result_class.new(0.9, nil), fake_search_result_class.new(0.7, nil) ],
      fake_cross_encoder_class.new(0.8)
    )

    result = Documents::ConfidenceScoreService.call(
      retrieval_result: retrieval_result,
      citation_result: fake_citation_result_class.new(0.5),
      groundedness_result: fake_groundedness_result_class.new(true, false),
      hallucination_result: fake_hallucination_result_class.new(0.0)
    )

    expect(0.0..1.0).to include(result.score)
    expect(result.components.size).to eq(5)
    expect(result.level).to eq(:high)
  end

  it "gives refused answers partial groundedness credit" do
    retrieval_result = fake_retrieval_result_class.new([], nil)

    refused = Documents::ConfidenceScoreService.call(
      retrieval_result: retrieval_result,
      groundedness_result: fake_groundedness_result_class.new(true, true)
    )

    ungrounded = Documents::ConfidenceScoreService.call(
      retrieval_result: retrieval_result,
      groundedness_result: fake_groundedness_result_class.new(false, false)
    )

    expect(refused.score).to be > ungrounded.score
  end

  it "excludes missing signals instead of treating them as zero" do
    retrieval_result = fake_retrieval_result_class.new([], nil)

    result = Documents::ConfidenceScoreService.call(
      retrieval_result: retrieval_result,
      groundedness_result: fake_groundedness_result_class.new(true, false)
    )

    expect(result.components.size).to eq(1)
    expect(result.score).to eq(1.0)
  end

  it "raises when there is no usable signal at all" do
    retrieval_result = fake_retrieval_result_class.new([], nil)

    expect do
      Documents::ConfidenceScoreService.call(retrieval_result: retrieval_result)
    end.to raise_error(Documents::ConfidenceScoreService::InvalidComponentsError)
  end
end
