require "rails_helper"

RSpec.describe Documents::CrossEncoder::Result do
  it "empty? reflects whether results is empty" do
    empty_result = Documents::CrossEncoder::Result.new(
      results: [], scores: {}, original_count: 0, evaluated_count: 0,
      reranked_count: 0, average_score: 0.0, duration_ms: 1.0, model: "m", strategy: "s"
    )
    expect(empty_result.empty?).to be_truthy

    non_empty_result = Documents::CrossEncoder::Result.new(
      results: [ :something ], scores: {}, original_count: 1, evaluated_count: 1,
      reranked_count: 1, average_score: 0.9, duration_ms: 1.0, model: "m", strategy: "s"
    )
    expect(non_empty_result.empty?).to be_falsey
  end
end
