# frozen_string_literal: true

FactoryBot.define do
  factory :rag_answer do
    association :rag_query
    answer { "Resposta de teste." }
    model { "fake-model" }
  end
end
