# frozen_string_literal: true

class RagAnswer < ApplicationRecord
  belongs_to :rag_query
  has_many :rag_feedbacks, dependent: :destroy

  validates :answer, presence: true
end
