# frozen_string_literal: true

FactoryBot.define do
  factory :rag_eval_result do
    association :rag_eval_run
    association :rag_eval_case
    errored { false }
  end
end
