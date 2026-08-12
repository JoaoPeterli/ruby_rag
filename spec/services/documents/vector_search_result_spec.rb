require "rails_helper"

RSpec.describe Documents::VectorSearchResult do
  it "exposes the given attributes" do
    result = Documents::VectorSearchResult.new(
      chunk_id: 1, document_id: 2, content: "conteúdo", position: 1,
      distance: 0.1, score: 0.9, metadata: { ramo: "auto" }
    )

    expect(result.chunk_id).to eq(1)
    expect(result.document_id).to eq(2)
    expect(result.content).to eq("conteúdo")
    expect(result.score).to eq(0.9)
    expect(result.metadata).to eq({ ramo: "auto" })
  end
end
