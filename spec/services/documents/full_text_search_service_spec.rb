require "rails_helper"

RSpec.describe Documents::FullTextSearchService do
  let(:document) { create(:document, title: "Manual de Averbação") }

  def build_chunk(content:, position:)
    document.document_chunks.create!(content: content, position: position, embedding: Array.new(1536, 0.01))
  end

  it "finds and ranks chunks by textual relevance to the query" do
    strong_match = build_chunk(
      content: "A apólice de seguro deve ser localizada antes da averbação. " \
               "A apólice e a averbação são revisadas em conjunto.",
      position: 0
    )
    weak_match = build_chunk(content: "A apólice trata da averbação uma única vez.", position: 1)
    unrelated = build_chunk(content: "Este trecho fala sobre outro assunto qualquer.", position: 2)

    results = Documents::FullTextSearchService.call(query: "apólice averbação")

    chunk_ids = results.map { |result| result.chunk.id }
    expect(chunk_ids).to include(strong_match.id, weak_match.id)
    expect(chunk_ids).not_to include(unrelated.id)
    expect(results.first.text_score).to be >= results.last.text_score
  end

  it "assigns sequential positions starting at 1" do
    build_chunk(content: "A apólice foi localizada com sucesso.", position: 0)
    build_chunk(content: "A apólice foi localizada em outro momento.", position: 1)

    results = Documents::FullTextSearchService.call(query: "apólice localizada")

    expect(results.map(&:position)).to eq([ 1, 2 ])
  end

  it "respects the limit" do
    3.times { |index| build_chunk(content: "A apólice número #{index} foi localizada.", position: index) }

    results = Documents::FullTextSearchService.call(query: "apólice localizada", limit: 2)

    expect(results.size).to eq(2)
  end

  it "raises for a blank query" do
    expect do
      Documents::FullTextSearchService.call(query: "   ")
    end.to raise_error(Documents::FullTextSearchService::InvalidQueryError)
  end

  it "raises for a non-positive limit" do
    expect do
      Documents::FullTextSearchService.call(query: "apólice", limit: 0)
    end.to raise_error(Documents::FullTextSearchService::InvalidLimitError)
  end

  it "returns no results when nothing matches the query" do
    build_chunk(content: "Texto totalmente não relacionado.", position: 0)

    results = Documents::FullTextSearchService.call(query: "termoinexistentequalquer")

    expect(results).to be_empty
  end
end
