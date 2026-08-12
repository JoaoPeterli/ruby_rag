require "rails_helper"

RSpec.describe Documents::ChunkWithOverlap do
  it "prefixes the content with the overlap text and a separator" do
    chunk = Documents::ChunkWithOverlap.new(content: "conteúdo novo", overlap: "fim do anterior")

    expect(chunk.overlap?).to be_truthy
    expect(chunk.text).to eq("fim do anterior\n\nconteúdo novo")
  end

  it "accepts a custom separator" do
    chunk = Documents::ChunkWithOverlap.new(content: "b", overlap: "a")

    expect(chunk.text(separator: " | ")).to eq("a | b")
  end

  it "returns only the content when there is no overlap" do
    chunk = Documents::ChunkWithOverlap.new(content: "conteúdo sozinho")

    expect(chunk.overlap?).to be_falsey
    expect(chunk.text).to eq("conteúdo sozinho")
  end

  it "treats a blank overlap the same as no overlap" do
    chunk = Documents::ChunkWithOverlap.new(content: "conteúdo", overlap: "   ")

    expect(chunk.overlap?).to be_falsey
    expect(chunk.text).to eq("conteúdo")
  end

  it "strips whitespace from both content and overlap" do
    chunk = Documents::ChunkWithOverlap.new(content: "  conteúdo  ", overlap: "  overlap  ")

    expect(chunk.text).to eq("overlap\n\nconteúdo")
  end
end
