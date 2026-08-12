require "rails_helper"

RSpec.describe Documents::RecursiveChunker do
  it "returns the whole text as a single chunk when under the size limit" do
    text = "Um parágrafo curto sobre averbação."

    expect(Documents::RecursiveChunker.call(text)).to eq([ text ])
  end

  it "splits on markdown headers first when the text exceeds the size limit" do
    text = ("x" * 300) + "\n#Bloco2\n" + ("y" * 300) + "\n#Bloco3\n" + ("z" * 500)

    chunks = Documents::RecursiveChunker.call(text)

    expect(chunks.size).to eq(3)
    chunks.each { |chunk| expect(chunk.length).to be <= 1000 }
    expect(chunks.first).to eq("x" * 300)
  end

  it "falls back to token-level hard splitting when no separator helps" do
    text = "a" * 2500

    chunks = Documents::RecursiveChunker.call(text)

    expect(chunks.map(&:length)).to eq([ 1000, 1000, 500 ])
    expect(chunks.join).to eq(text)
  end

  it "strips surrounding whitespace from the input" do
    expect(Documents::RecursiveChunker.call("   conteúdo   ")).to eq([ "conteúdo" ])
  end
end
