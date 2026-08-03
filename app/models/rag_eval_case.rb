# frozen_string_literal: true

class RagEvalCase < ApplicationRecord
  belongs_to :account, optional: true

  validates :question, presence: true

  scope :active, -> { where(active: true) }
  scope :by_category, ->(category) { where(category: category) }

  def expects_answer?
    expected_answer.present?
  end
end
