# frozen_string_literal: true

FactoryBot.define do
  factory :rag_feedback do
    association :rag_answer
    rating { "positive" }
  end
end
