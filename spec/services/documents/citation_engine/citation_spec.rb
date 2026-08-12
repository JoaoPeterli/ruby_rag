require "rails_helper"

RSpec.describe Documents::CitationEngine::Citation do
  it "exposes the given attributes" do
    citation = Documents::CitationEngine::Citation.new(
      source_number: 1,
      chunk_id: 42,
      document_id: 7,
      position: 3
    )

    expect(citation.source_number).to eq(1)
    expect(citation.chunk_id).to eq(42)
    expect(citation.document_id).to eq(7)
    expect(citation.position).to eq(3)
  end

  it "two citations with the same attributes are equal" do
    a = Documents::CitationEngine::Citation.new(source_number: 1, chunk_id: 1, document_id: 1, position: 1)
    b = Documents::CitationEngine::Citation.new(source_number: 1, chunk_id: 1, document_id: 1, position: 1)

    expect(a).to eq(b)
  end
end
