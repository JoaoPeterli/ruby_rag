require "rails_helper"

RSpec.describe Documents::Chunker do
  it "splits a single paragraph into overlapping fixed-size windows" do
    text = "a" * 25

    chunks = Documents::Chunker.new(text, size: 10, overlap: 3).call

    expect(chunks).to eq([ "a" * 10, "a" * 10, "a" * 10, "a" * 4 ])
  end

  it "starts a new sequence of chunks for each blank-line-separated paragraph" do
    text = "Primeiro parágrafo curto.\n\nSegundo parágrafo curto."

    chunks = Documents::Chunker.new(text, size: 1000, overlap: 100).call

    expect(chunks).to eq([ "Primeiro parágrafo curto.", "Segundo parágrafo curto." ])
  end

  it "call is a shorthand for .new(text).call with default size and overlap" do
    text = "texto curto sem necessidade de quebra"

    expect(Documents::Chunker.call(text)).to eq(Documents::Chunker.new(text).call)
  end

  it "returns an empty array for blank text" do
    expect(Documents::Chunker.new("").call).to eq([])
  end
end
