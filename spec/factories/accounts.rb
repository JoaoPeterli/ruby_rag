# frozen_string_literal: true

FactoryBot.define do
  factory :account do
    sequence(:name) { |n| "Conta de Teste #{n}" }
    operator { false }
    active { true }
  end
end
