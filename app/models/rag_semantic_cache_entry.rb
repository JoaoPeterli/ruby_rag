# frozen_string_literal: true

class RagSemanticCacheEntry < ApplicationRecord
  belongs_to :account, optional: true

  has_neighbors :question_embedding

  validates :question, presence: true
  validates :answer, presence: true

  scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
end
