require "rails_helper"

RSpec.describe Documents::CitationEngine::Service do
  def sources
    [
      { source_number: 1, chunk_id: 101, document_id: 1, position: 1 },
      { source_number: 2, chunk_id: 102, document_id: 1, position: 2 },
      { source_number: 3, chunk_id: 103, document_id: 1, position: 3 },
      { source_number: 4, chunk_id: 104, document_id: 1, position: 4 }
    ].freeze
  end

  it "parses single citations" do
    result = Documents::CitationEngine::Service.call(
      answer: "O sistema faz X [FONTE 1] e Y [FONTE 2].",
      sources: sources
    )

    expect(result.cited_source_numbers).to eq([ 1, 2 ])
    expect(result.cited_chunk_ids).to eq([ 101, 102 ])
  end

  it "parses comma-separated and range citations" do
    result = Documents::CitationEngine::Service.call(
      answer: "Ver [FONTE 1, FONTE 3] e também [FONTE 2 a 4].",
      sources: sources
    )

    expect(result.cited_source_numbers).to eq([ 1, 2, 3, 4 ])
  end

  it "computes coverage and uncited sources" do
    result = Documents::CitationEngine::Service.call(
      answer: "Apenas [FONTE 1].",
      sources: sources
    )

    expect(result.citation_coverage).to eq(0.25)
    expect(result.uncited_source_numbers).to eq([ 2, 3, 4 ])
  end

  it "ignores citation numbers that do not match any source" do
    result = Documents::CitationEngine::Service.call(
      answer: "Fonte inexistente [FONTE 99].",
      sources: sources
    )

    expect(result.citation_count).to eq(0)
  end

  it "answer without citations yields zero coverage" do
    result = Documents::CitationEngine::Service.call(
      answer: "Não encontrei informações suficientes.",
      sources: sources
    )

    expect(result.any_citations?).to be_falsey
    expect(result.citation_coverage).to eq(0.0)
  end

  it "raises for invalid sources" do
    expect do
      Documents::CitationEngine::Service.call(answer: "texto", sources: nil)
    end.to raise_error(Documents::CitationEngine::Service::InvalidSourcesError)
  end
end
