# frozen_string_literal: true

class AdminAuditLog < ApplicationRecord
  belongs_to :account

  validates :action, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
end
