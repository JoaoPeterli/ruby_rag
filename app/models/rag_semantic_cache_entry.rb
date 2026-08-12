# frozen_string_literal: true

class RagSemanticCacheEntry < ApplicationRecord
  belongs_to :account, optional: true

  validates :question, presence: true
  validates :answer, presence: true

  scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  after_destroy :delete_from_vector_store

  private

  def delete_from_vector_store
    Ai::VectorStoreService.default.delete(
      collection: Ai::Configuration::QDRANT_SEMANTIC_CACHE_COLLECTION,
      ids: [ id ]
    )
  end
end
