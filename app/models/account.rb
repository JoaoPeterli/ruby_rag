# frozen_string_literal: true

require "securerandom"

class Account < ApplicationRecord
  has_many :documents, dependent: :nullify
  has_many :document_chunks, dependent: :nullify
  has_many :rag_queries, dependent: :nullify
  has_many :rag_eval_cases, dependent: :nullify

  before_validation :generate_api_key, on: :create

  validates :name, presence: true
  validates :api_key, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }

  private

  def generate_api_key
    self.api_key ||= SecureRandom.hex(32)
  end
end
