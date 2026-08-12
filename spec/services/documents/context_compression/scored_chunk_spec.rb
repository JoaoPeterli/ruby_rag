require "rails_helper"

RSpec.describe Documents::ContextCompression::ScoredChunk do
  it "exposes chunk, similarity and source" do
    scored = Documents::ContextCompression::ScoredChunk.new(chunk: :a_chunk, similarity: 0.87, source: true)

    expect(scored.chunk).to eq(:a_chunk)
    expect(scored.similarity).to eq(0.87)
    expect(scored.source).to be_truthy
  end
end
