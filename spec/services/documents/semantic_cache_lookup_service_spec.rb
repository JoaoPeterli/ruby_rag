require "rails_helper"

RSpec.describe Documents::SemanticCacheLookupService do
  def identical_embedding
    Array.new(1536, 0.0).tap { |vector| vector[0] = 1.0 }
  end

  def orthogonal_embedding
    Array.new(1536, 0.0).tap { |vector| vector[1] = 1.0 }
  end

  def build_entry(embedding, expires_at:)
    entry = RagSemanticCacheEntry.create!(question: "pergunta antiga", answer: "resposta", expires_at: expires_at)

    Ai::VectorStoreService.default.upsert(
      collection: Ai::Configuration::QDRANT_SEMANTIC_CACHE_COLLECTION,
      id: entry.id,
      vector: embedding
    )

    entry
  end

  it "returns nil when there is no cache entry at all" do
    expect(Documents::SemanticCacheLookupService.call(question_embedding: identical_embedding)).to be_nil
  end

  it "returns nil when the closest entry is not similar enough" do
    build_entry(orthogonal_embedding, expires_at: 1.hour.from_now)

    expect(Documents::SemanticCacheLookupService.call(question_embedding: identical_embedding)).to be_nil
  end

  it "returns the entry and its similarity when the match crosses the threshold, and registers a hit" do
    entry = build_entry(identical_embedding, expires_at: 1.hour.from_now)

    result = Documents::SemanticCacheLookupService.call(question_embedding: identical_embedding)

    expect(result.entry.id).to eq(entry.id)
    expect(result.similarity).to be_within(0.001).of(1.0)

    entry.reload
    expect(entry.hits).to eq(1)
    expect(entry.last_hit_at).to be_present
  end

  it "ignores expired entries via the default scope" do
    build_entry(identical_embedding, expires_at: 1.hour.ago)

    expect(Documents::SemanticCacheLookupService.call(question_embedding: identical_embedding)).to be_nil
  end

  it "raises for an invalid embedding" do
    expect do
      Documents::SemanticCacheLookupService.call(question_embedding: [])
    end.to raise_error(Documents::SemanticCacheLookupService::InvalidEmbeddingError)

    expect do
      Documents::SemanticCacheLookupService.call(question_embedding: [ "não numérico" ])
    end.to raise_error(Documents::SemanticCacheLookupService::InvalidEmbeddingError)
  end
end
