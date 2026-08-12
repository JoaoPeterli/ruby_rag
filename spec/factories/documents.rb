# frozen_string_literal: true

FactoryBot.define do
  factory :document do
    association :account
    sequence(:title) { |n| "Documento #{n}" }
    content { "Conteúdo de teste do documento." }
    status { "completed" }
  end
end
