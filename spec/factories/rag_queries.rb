# frozen_string_literal: true

FactoryBot.define do
  factory :rag_query do
    association :account
    sequence(:question) { |n| "Pergunta de teste #{n}?" }
    status { "completed" }
  end
end
