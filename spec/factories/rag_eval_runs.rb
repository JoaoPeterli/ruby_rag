# frozen_string_literal: true

FactoryBot.define do
  factory :rag_eval_run do
    cases_count { 0 }
    started_at { Time.current }
    finished_at { Time.current }
  end
end
