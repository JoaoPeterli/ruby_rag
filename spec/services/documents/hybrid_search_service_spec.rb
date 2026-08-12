require "rails_helper"

RSpec.describe Documents::HybridSearchService do
  let(:document) { create(:document) }

  def build_chunk(document, position:, content: "Conteúdo #{position}")
    document.document_chunks.create!(content: content, position: position, embedding: Array.new(1536, 0.01))
  end

  it "blends vector similarity and normalized text score with a 70/30 weight" do
    chunk = build_chunk(document, position: 0)

    vector_result = Documents::VectorSearchService::Result.new(
      chunk: chunk, distance: 0.1, similarity: 0.9, position: 1
    )
    text_result = Documents::FullTextSearchService::Result.new(
      chunk: chunk, text_score: 8.0, position: 1
    )

    results = Documents::HybridSearchService.call(
      vector_results: [ vector_result ],
      text_results: [ text_result ]
    )

    result = results.first
    expect(result.similarity).to be_within(0.0001).of(0.9)
    expect(result.normalized_text_score).to be_within(0.0001).of(1.0)
    expect(result.hybrid_score).to be_within(0.0001).of((0.9 * 0.70) + (1.0 * 0.30))
  end

  it "normalizes text scores relative to the maximum among the text results" do
    chunk_a = build_chunk(document, position: 0)
    chunk_b = build_chunk(document, position: 1)

    vector_results = [
      Documents::VectorSearchService::Result.new(chunk: chunk_a, distance: 0.1, similarity: 0.9, position: 1),
      Documents::VectorSearchService::Result.new(chunk: chunk_b, distance: 0.2, similarity: 0.5, position: 2)
    ]
    text_results = [
      Documents::FullTextSearchService::Result.new(chunk: chunk_a, text_score: 8.0, position: 1),
      Documents::FullTextSearchService::Result.new(chunk: chunk_b, text_score: 4.0, position: 2)
    ]

    results = Documents::HybridSearchService.call(
      vector_results: vector_results,
      text_results: text_results
    )

    by_chunk = results.index_by(&:chunk)
    expect(by_chunk[chunk_a].normalized_text_score).to be_within(0.0001).of(1.0)
    expect(by_chunk[chunk_b].normalized_text_score).to be_within(0.0001).of(0.5)
  end

  it "treats a chunk found only by vector search as having zero text score" do
    vector_only = build_chunk(document, position: 0)
    text_only = build_chunk(document, position: 1)

    results = Documents::HybridSearchService.call(
      vector_results: [
        Documents::VectorSearchService::Result.new(chunk: vector_only, distance: 0.1, similarity: 0.8, position: 1)
      ],
      text_results: [
        Documents::FullTextSearchService::Result.new(chunk: text_only, text_score: 5.0, position: 1)
      ]
    )

    by_chunk = results.index_by(&:chunk)

    expect(by_chunk[vector_only].normalized_text_score).to be_within(0.0001).of(0.0)
    expect(by_chunk[vector_only].hybrid_score).to be_within(0.0001).of(0.8 * 0.70)

    expect(by_chunk[text_only].similarity).to be_within(0.0001).of(0.0)
    expect(by_chunk[text_only].hybrid_score).to be_within(0.0001).of(1.0 * 0.30)
  end

  it "does not divide by zero when every text score is zero" do
    chunk = build_chunk(document, position: 0)

    results = Documents::HybridSearchService.call(
      vector_results: [
        Documents::VectorSearchService::Result.new(chunk: chunk, distance: 0.1, similarity: 0.7, position: 1)
      ],
      text_results: [
        Documents::FullTextSearchService::Result.new(chunk: chunk, text_score: 0.0, position: 1)
      ]
    )

    expect(results.first.normalized_text_score).to be_within(0.0001).of(0.0)
  end

  it "deduplicates a chunk that appears in both result sets and sorts by hybrid_score" do
    strong = build_chunk(document, position: 0)
    weak = build_chunk(document, position: 1)

    results = Documents::HybridSearchService.call(
      vector_results: [
        Documents::VectorSearchService::Result.new(chunk: strong, distance: 0.05, similarity: 0.95, position: 1),
        Documents::VectorSearchService::Result.new(chunk: weak, distance: 0.4, similarity: 0.3, position: 2)
      ],
      text_results: [
        Documents::FullTextSearchService::Result.new(chunk: strong, text_score: 9.0, position: 1),
        Documents::FullTextSearchService::Result.new(chunk: weak, text_score: 1.0, position: 2)
      ]
    )

    expect(results.size).to eq(2)
    expect(results.map(&:chunk)).to eq([ strong, weak ])
    expect(results.map(&:position)).to eq([ 1, 2 ])
  end

  it "respects the limit and reassigns sequential positions" do
    chunks = Array.new(3) { |index| build_chunk(document, position: index) }

    vector_results = chunks.each_with_index.map do |chunk, index|
      Documents::VectorSearchService::Result.new(
        chunk: chunk, distance: 0.1, similarity: 1.0 - (index * 0.1), position: index + 1
      )
    end

    results = Documents::HybridSearchService.call(
      vector_results: vector_results,
      text_results: [],
      limit: 2
    )

    expect(results.size).to eq(2)
    expect(results.map(&:position)).to eq([ 1, 2 ])
  end

  it "raises for malformed vector results" do
    expect do
      Documents::HybridSearchService.call(
        vector_results: [ { chunk: nil } ],
        text_results: []
      )
    end.to raise_error(Documents::HybridSearchService::InvalidVectorResultsError)
  end

  it "raises for malformed text results" do
    chunk = build_chunk(document, position: 0)

    expect do
      Documents::HybridSearchService.call(
        vector_results: [],
        text_results: [ { chunk: chunk } ]
      )
    end.to raise_error(Documents::HybridSearchService::InvalidTextResultsError)
  end

  it "raises for a non-positive limit" do
    expect do
      Documents::HybridSearchService.call(
        vector_results: [],
        text_results: [],
        limit: 0
      )
    end.to raise_error(Documents::HybridSearchService::InvalidLimitError)
  end
end
