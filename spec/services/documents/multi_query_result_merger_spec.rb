require "rails_helper"

RSpec.describe Documents::MultiQueryResultMerger do
  let(:document) { create(:document) }

  def build_chunk(position:)
    document.document_chunks.create!(content: "Conteúdo #{position}.", position: position, embedding: Array.new(1536, 0.01))
  end

  def hybrid_result(chunk:, hybrid_score:, position: 1)
    Documents::HybridSearchService::Result.new(
      chunk: chunk, distance: nil, similarity: hybrid_score, vector_position: position, text_position: nil,
      text_score: 0.0, normalized_text_score: 0.0, hybrid_score: hybrid_score, position: position
    )
  end

  it "merges the same chunk found by two different queries, keeping the entry with the higher hybrid_score" do
    chunk = build_chunk(position: 0)

    merged = Documents::MultiQueryResultMerger.call(
      query_results: [
        { query: "pergunta original", query_position: 1, results: [ hybrid_result(chunk: chunk, hybrid_score: 0.4) ] },
        { query: "pergunta reescrita", query_position: 2, results: [ hybrid_result(chunk: chunk, hybrid_score: 0.6) ] }
      ]
    )

    result = merged.first
    expect(merged.size).to eq(1)
    expect(result.matched_queries).to eq([ "pergunta original", "pergunta reescrita" ])
    expect(result.query_match_count).to eq(2)
    expect(result.similarity).to be_within(0.0001).of(0.6) # veio da entrada de maior hybrid_score
    # bonus de frequência: min(count - 1, 3) * 0.05 = min(1, 3) * 0.05 = 0.05
    expect(result.multi_query_score).to be_within(0.0001).of(0.65)
  end

  it "caps the frequency bonus at three extra query matches" do
    chunk = build_chunk(position: 0)

    entries = (1..5).map do |index|
      { query: "consulta #{index}", query_position: index, results: [ hybrid_result(chunk: chunk, hybrid_score: 0.5) ] }
    end

    result = Documents::MultiQueryResultMerger.call(query_results: entries).first

    expect(result.query_match_count).to eq(5)
    # min(5 - 1, 3) * 0.05 = 0.15, não 0.20
    expect(result.multi_query_score).to be_within(0.0001).of(0.65)
  end

  it "clamps the multi_query_score at 1.0" do
    chunk = build_chunk(position: 0)

    entries = (1..4).map do |index|
      { query: "consulta #{index}", query_position: index, results: [ hybrid_result(chunk: chunk, hybrid_score: 0.95) ] }
    end

    result = Documents::MultiQueryResultMerger.call(query_results: entries).first

    expect(result.multi_query_score).to be_within(0.0001).of(1.0)
  end

  it "sorts by multi_query_score, respects the limit and reassigns sequential positions" do
    strong = build_chunk(position: 0)
    weak = build_chunk(position: 1)

    results = Documents::MultiQueryResultMerger.call(
      query_results: [
        {
          query: "consulta", query_position: 1,
          results: [ hybrid_result(chunk: weak, hybrid_score: 0.3), hybrid_result(chunk: strong, hybrid_score: 0.9) ]
        }
      ],
      limit: 1
    )

    expect(results.map(&:chunk)).to eq([ strong ])
    expect(results.map(&:position)).to eq([ 1 ])
  end

  it "raises for malformed query_results" do
    expect do
      Documents::MultiQueryResultMerger.call(query_results: [ { query: "x" } ])
    end.to raise_error(Documents::MultiQueryResultMerger::InvalidResultsError)
  end

  it "raises for a non-positive limit" do
    chunk = build_chunk(position: 0)

    expect do
      Documents::MultiQueryResultMerger.call(
        query_results: [ { query: "q", query_position: 1, results: [ hybrid_result(chunk: chunk, hybrid_score: 0.5) ] } ],
        limit: 0
      )
    end.to raise_error(Documents::MultiQueryResultMerger::InvalidLimitError)
  end
end
