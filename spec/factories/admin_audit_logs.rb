# frozen_string_literal: true

FactoryBot.define do
  factory :admin_audit_log do
    association :account
    action { "account.created" }
    details { {} }
  end
end
