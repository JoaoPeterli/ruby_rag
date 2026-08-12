# frozen_string_literal: true

FactoryBot.define do
  factory :rag_eval_case do
    association :account
    sequence(:question) { |n| "Pergunta de avaliação #{n}?" }
    active { true }
  end
end
