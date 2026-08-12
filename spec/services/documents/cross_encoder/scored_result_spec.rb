require "rails_helper"

RSpec.describe Documents::CrossEncoder::ScoredResult do
  it "chunk delegates to result.chunk" do
    inner_result = Documents::VectorSearchService::Result.new(
      chunk: "chunk-double", distance: 0.1, similarity: 0.5, position: 1
    )

    scored = Documents::CrossEncoder::ScoredResult.new(
      result: inner_result,
      cross_encoder_score: 0.8,
      cross_encoder_reason: "motivo",
      retrieval_score: 0.5,
      combined_score: 0.7
    )

    expect(scored.chunk).to eq("chunk-double")
  end
end
