require "rails_helper"

RSpec.describe RagSemanticCacheEntry do
  def build_entry(**overrides)
    build(:rag_semantic_cache_entry, **overrides)
  end

  it "requires question and answer" do
    entry = build_entry(question: nil, answer: nil)

    expect(entry).not_to be_valid
    expect(entry.errors.attribute_names).to include(:question, :answer)
  end

  it "deletes the entry's point from the vector store after destroy" do
    entry = build_entry
    entry.save!

    Ai::VectorStoreService.default.upsert(
      collection: Ai::Configuration::QDRANT_SEMANTIC_CACHE_COLLECTION,
      id: entry.id,
      vector: Array.new(1536, 0.0)
    )

    entry.destroy!

    expect(
      Ai::VectorStoreService.default.retrieve(
        collection: Ai::Configuration::QDRANT_SEMANTIC_CACHE_COLLECTION,
        ids: [ entry.id ]
      )
    ).to be_empty
  end

  it "excludes expired entries via the not_expired scope" do
    fresh = build_entry(expires_at: 1.hour.from_now)
    fresh.save!
    stale = build_entry(question: "Outra pergunta", expires_at: 1.hour.ago)
    stale.save!
    no_expiry = build_entry(question: "Sem expiracao", expires_at: nil)
    no_expiry.save!

    result = RagSemanticCacheEntry.not_expired

    expect(result).to include(fresh, no_expiry)
    expect(result).not_to include(stale)
  end
end
