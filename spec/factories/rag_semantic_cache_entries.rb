# frozen_string_literal: true

FactoryBot.define do
  factory :rag_semantic_cache_entry do
    sequence(:question) { |n| "Pergunta em cache #{n}?" }
    answer { "Resposta em cache." }
    expires_at { 1.hour.from_now }
  end
end
