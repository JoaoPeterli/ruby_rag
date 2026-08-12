require "rails_helper"

RSpec.describe Documents::SemanticDeduplicationService do
  let(:document) { create(:document) }

  def build_chunk(embedding, position:, content: "Conteúdo #{position}")
    chunk = document.document_chunks.create!(content: content, position: position, embedding: embedding)

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

  it "finds near-identical chunks above the similarity threshold, excluding the source chunk itself" do
    source = build_chunk(base_embedding, position: 0)
    duplicate = build_chunk(base_embedding, position: 1)

    result = Documents::SemanticDeduplicationService.call(chunk: source)

    expect(result.chunk).to eq(source)
    expect(result.duplicate_count).to eq(1)
    expect(result.duplicates.first.chunk).to eq(duplicate)
    expect(result.duplicates.first.similarity).to be_within(0.001).of(1.0)
  end

  it "returns no duplicates when nothing is close enough" do
    source = build_chunk(base_embedding, position: 0)
    build_chunk(orthogonal_embedding, position: 1)

    result = Documents::SemanticDeduplicationService.call(chunk: source)

    expect(result.duplicate_count).to eq(0)
    expect(result.duplicates).to be_empty
  end

  it "respects the limit of candidates considered" do
    source = build_chunk(base_embedding, position: 0)
    3.times { |index| build_chunk(base_embedding, position: index + 1) }

    result = Documents::SemanticDeduplicationService.call(chunk: source, limit: 2)

    expect(result.duplicate_count).to eq(2)
  end

  it "raises for an unpersisted chunk" do
    unsaved = DocumentChunk.new(content: "x", position: 0, embedding: base_embedding)

    expect do
      Documents::SemanticDeduplicationService.call(chunk: unsaved)
    end.to raise_error(Documents::SemanticDeduplicationService::InvalidChunkError)
  end

  it "raises for a chunk without a valid embedding" do
    chunk = document.document_chunks.create!(content: "sem embedding", position: 0)

    expect do
      Documents::SemanticDeduplicationService.call(chunk: chunk)
    end.to raise_error(Documents::SemanticDeduplicationService::InvalidChunkError)
  end
end
