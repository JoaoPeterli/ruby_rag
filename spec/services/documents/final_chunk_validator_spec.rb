require "rails_helper"

RSpec.describe Documents::FinalChunkValidator do
  it "returns the content untouched when there is no overlap" do
    chunk = Documents::ChunkWithOverlap.new(content: "Conteúdo principal.")

    result = Documents::FinalChunkValidator.call([ chunk ])

    expect(result).to eq([ "Conteúdo principal." ])
  end

  it "joins the overlap and the content when they fit within the token budget" do
    chunk = Documents::ChunkWithOverlap.new(content: "Conteúdo principal.", overlap: "Contexto anterior.")

    result = Documents::FinalChunkValidator.call([ chunk ], max_tokens: 500)

    expect(result.first).to eq("Contexto anterior.\n\nConteúdo principal.")
  end

  it "trims the overlap word by word until it fits the token budget" do
    long_overlap = Array.new(200) { "palavra" }.join(" ")
    chunk = Documents::ChunkWithOverlap.new(content: "Conteúdo principal curto.", overlap: long_overlap)

    result = Documents::FinalChunkValidator.call([ chunk ], max_tokens: 20)

    expect(result.first).to end_with("Conteúdo principal curto.")
    expect(Ai::Tokenizer.count(result.first)).to be <= 20
  end

  it "raises when the main content alone already exceeds the token budget" do
    huge_content = Array.new(500) { "palavra" }.join(" ")
    chunk = Documents::ChunkWithOverlap.new(content: huge_content)

    expect do
      Documents::FinalChunkValidator.call([ chunk ], max_tokens: 20)
    end.to raise_error(Documents::FinalChunkValidator::ContentTooLargeError)
  end

  it "raises ArgumentError for a chunk of the wrong type" do
    expect do
      Documents::FinalChunkValidator.call([ { content: "x", overlap: "" } ])
    end.to raise_error(ArgumentError)
  end
end
