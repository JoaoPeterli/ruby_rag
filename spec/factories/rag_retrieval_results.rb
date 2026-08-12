# frozen_string_literal: true

FactoryBot.define do
  factory :rag_retrieval_result do
    association :rag_query
    association :document_chunk
    position { 1 }
    cited { false }
  end
end
