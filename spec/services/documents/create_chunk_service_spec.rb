require "rails_helper"

RSpec.describe Documents::CreateChunkService do
  let(:account) { create(:account) }
  let(:document) { create(:document, account: account) }

  it "creates a chunk with the embedding returned by the embedding service" do
    embedding = Array.new(1536, 0.02)
    allow(Ai::EmbeddingService).to receive(:call).and_return([ embedding ])

    chunk = Documents::CreateChunkService.call(
      document: document,
      content: "Texto do chunk.",
      position: 0,
      metadata: { "source" => "teste" }
    )

    expect(chunk).to be_persisted
    expect(chunk.content).to eq("Texto do chunk.")
    expect(chunk.position).to eq(0)
    expect(chunk.metadata).to eq({ "source" => "teste" })
    expect(chunk.embedding.to_a.size).to eq(1536)
    expect(chunk.embedding.to_a.first).to be_within(0.001).of(0.02)
  end

  it "raises for an unpersisted document" do
    expect do
      Documents::CreateChunkService.call(document: Document.new, content: "Texto", position: 0)
    end.to raise_error(Documents::CreateChunkService::Error)
  end

  it "raises for blank content" do
    expect do
      Documents::CreateChunkService.call(document: document, content: "   ", position: 0)
    end.to raise_error(Documents::CreateChunkService::Error)
  end

  it "raises for a nil position" do
    expect do
      Documents::CreateChunkService.call(document: document, content: "Texto", position: nil)
    end.to raise_error(Documents::CreateChunkService::Error)
  end

  it "wraps a validation failure as Error" do
    document.document_chunks.create!(content: "Já existe.", position: 0, embedding: Array.new(1536, 0.01))
    allow(Ai::EmbeddingService).to receive(:call).and_return([ Array.new(1536, 0.01) ])

    expect do
      Documents::CreateChunkService.call(document: document, content: "Outro texto qualquer.", position: 0)
    end.to raise_error(Documents::CreateChunkService::Error)
  end
end
