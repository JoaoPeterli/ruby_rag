# frozen_string_literal: true

class RagFeedback < ApplicationRecord
  RATINGS = %w[positive negative].freeze

  belongs_to :rag_answer

  validates :rating, inclusion: { in: RATINGS }
end
