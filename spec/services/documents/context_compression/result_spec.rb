require "rails_helper"

RSpec.describe Documents::ContextCompression::Result do
  def build_result(original_count:, compressed_count:, chunks: [])
    Documents::ContextCompression::Result.new(
      chunks: chunks,
      removed_chunks: [],
      scores: {},
      original_count: original_count,
      compressed_count: compressed_count,
      compression_ratio: 0.0,
      duration_ms: 1.0,
      strategy: "SimilarityStrategy"
    )
  end

  it "compressed? is true when compressed_count is lower than original_count" do
    result = build_result(original_count: 10, compressed_count: 6)

    expect(result.compressed?).to be_truthy
    expect(result.removed_count).to eq(4)
  end

  it "compressed? is false when nothing was removed" do
    result = build_result(original_count: 5, compressed_count: 5)

    expect(result.compressed?).to be_falsey
    expect(result.removed_count).to eq(0)
  end

  it "empty? reflects whether the chunks list has any elements" do
    expect(build_result(original_count: 0, compressed_count: 0, chunks: []).empty?).to be_truthy
    expect(build_result(original_count: 1, compressed_count: 1, chunks: [ :chunk ]).empty?).to be_falsey
  end
end
