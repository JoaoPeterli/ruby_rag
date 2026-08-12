# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    association :account
    sequence(:email) { |n| "usuario#{n}@teste.com" }
    password { "senha1234" }
    active { true }
  end
end
