require "rails_helper"

RSpec.describe Documents::VectorSearchService do
  let(:document) { create(:document) }

  def build_chunk(embedding, position:)
    chunk = document.document_chunks.create!(content: "Conteúdo #{position}", position: position)

    Ai::VectorStoreService.default.upsert(
      collection: Ai::Configuration::QDRANT_DOCUMENT_CHUNKS_COLLECTION,
      id: chunk.id,
      vector: embedding,
      payload: { document_id: chunk.document_id, account_id: chunk.account_id, position: chunk.position }
    )

    chunk
  end

  def base_embedding
    Array.new(1536, 0.0).tap { |vector| vector[0] = 1.0 }
  end

  def orthogonal_embedding
    Array.new(1536, 0.0).tap { |vector| vector[1] = 1.0 }
  end

  it "returns chunks at or above the minimum similarity, closest first" do
    close = build_chunk(base_embedding, position: 0)

    results = Documents::VectorSearchService.call(
      query: "prazo da apólice", query_embedding: base_embedding
    )

    expect(results.size).to eq(1)
    expect(results.first.chunk).to eq(close)
    expect(results.first.similarity).to be_within(0.001).of(1.0)
    expect(results.first.position).to eq(1)
  end

  it "excludes chunks below the minimum similarity" do
    build_chunk(orthogonal_embedding, position: 0)

    results = Documents::VectorSearchService.call(
      query: "prazo da apólice", query_embedding: base_embedding, minimum_similarity: 0.55
    )

    expect(results).to be_empty
  end

  it "respects the limit" do
    3.times { |index| build_chunk(base_embedding, position: index) }

    results = Documents::VectorSearchService.call(
      query: "prazo da apólice", query_embedding: base_embedding, limit: 2
    )

    expect(results.size).to eq(2)
  end

  it "raises for a blank query" do
    expect do
      Documents::VectorSearchService.call(query: "  ", query_embedding: base_embedding)
    end.to raise_error(Documents::VectorSearchService::InvalidQueryError)
  end

  it "raises for an invalid embedding" do
    expect do
      Documents::VectorSearchService.call(query: "prazo", query_embedding: [])
    end.to raise_error(Documents::VectorSearchService::InvalidEmbeddingError)
  end

  it "raises for a non-positive limit" do
    expect do
      Documents::VectorSearchService.call(query: "prazo", query_embedding: base_embedding, limit: 0)
    end.to raise_error(ArgumentError)
  end

  it "raises when candidate_limit is smaller than limit" do
    expect do
      Documents::VectorSearchService.call(
        query: "prazo", query_embedding: base_embedding, limit: 10, candidate_limit: 5
      )
    end.to raise_error(ArgumentError)
  end

  it "raises when minimum_similarity is out of range" do
    expect do
      Documents::VectorSearchService.call(query: "prazo", query_embedding: base_embedding, minimum_similarity: 1.5)
    end.to raise_error(ArgumentError)
  end
end
