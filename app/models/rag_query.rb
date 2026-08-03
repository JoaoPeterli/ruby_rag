# frozen_string_literal: true

class RagQuery < ApplicationRecord
  STATUSES = %w[completed failed].freeze

  belongs_to :account, optional: true

  has_one :rag_answer, dependent: :destroy
  has_many :rag_retrieval_results, dependent: :destroy

  validates :question, presence: true
  validates :status, inclusion: { in: STATUSES }
end
