require "rails_helper"

RSpec.describe Documents::CitationEngine::Result do
  def build_result(citations:, citation_count: citations.size)
    Documents::CitationEngine::Result.new(
      answer: "resposta",
      citations: citations,
      cited_source_numbers: citations.map(&:source_number),
      uncited_source_numbers: [],
      citation_count: citation_count,
      source_count: citations.size,
      citation_coverage: 1.0,
      duration_ms: 1.0
    )
  end

  it "cited_chunk_ids returns the unique chunk ids across all citations" do
    citations = [
      Documents::CitationEngine::Citation.new(source_number: 1, chunk_id: 10, document_id: 1, position: 1),
      Documents::CitationEngine::Citation.new(source_number: 2, chunk_id: 10, document_id: 1, position: 1),
      Documents::CitationEngine::Citation.new(source_number: 3, chunk_id: 20, document_id: 2, position: 1)
    ]

    result = build_result(citations: citations)

    expect(result.cited_chunk_ids).to eq([ 10, 20 ])
  end

  it "any_citations? is true when citation_count is positive" do
    result = build_result(citations: [
      Documents::CitationEngine::Citation.new(source_number: 1, chunk_id: 1, document_id: 1, position: 1)
    ])

    expect(result.any_citations?).to be_truthy
  end

  it "any_citations? is false when citation_count is zero" do
    result = build_result(citations: [], citation_count: 0)

    expect(result.any_citations?).to be_falsey
    expect(result.cited_chunk_ids).to eq([])
  end
end
