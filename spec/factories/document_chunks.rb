# frozen_string_literal: true

FactoryBot.define do
  factory :document_chunk do
    association :document
    sequence(:position) { |n| n }
    sequence(:content) { |n| "Trecho de teste #{n}." }
    metadata { {} }
  end
end
