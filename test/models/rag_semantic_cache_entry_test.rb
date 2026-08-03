require "test_helper"

class RagSemanticCacheEntryTest < ActiveSupport::TestCase
  def build_entry(**overrides)
    RagSemanticCacheEntry.new(
      {
        question: "Pergunta de teste",
        question_embedding: Array.new(1536, 0.0),
        answer: "Resposta em cache"
      }.merge(overrides)
    )
  end

  test "requires question and answer" do
    entry = build_entry(question: nil, answer: nil)

    assert_not entry.valid?
    assert_includes entry.errors.attribute_names, :question
    assert_includes entry.errors.attribute_names, :answer
  end

  test "persists a real embedding vector" do
    entry = build_entry
    entry.save!

    assert_equal 1536, entry.reload.question_embedding.size
  end

  test "not_expired scope excludes entries past their expiration" do
    fresh = build_entry(expires_at: 1.hour.from_now)
    fresh.save!
    stale = build_entry(question: "Outra pergunta", expires_at: 1.hour.ago)
    stale.save!
    no_expiry = build_entry(question: "Sem expiracao", expires_at: nil)
    no_expiry.save!

    result = RagSemanticCacheEntry.not_expired

    assert_includes result, fresh
    assert_includes result, no_expiry
    assert_not_includes result, stale
  end
end
