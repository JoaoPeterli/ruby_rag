require "rails_helper"

RSpec.describe AdminAuditLog do
  let(:account) { create(:account) }

  it "requires an action" do
    log = AdminAuditLog.new(account: account)

    expect(log).not_to be_valid
    expect(log.errors.attribute_names).to include(:action)
  end

  it "requires an account" do
    log = AdminAuditLog.new(action: "account.created")

    expect(log).not_to be_valid
    expect(log.errors.attribute_names).to include(:account)
  end

  it "orders by created_at descending via recent_first" do
    older = AdminAuditLog.create!(account: account, action: "a", created_at: 2.hours.ago)
    newer = AdminAuditLog.create!(account: account, action: "b", created_at: 1.hour.ago)

    expect(AdminAuditLog.recent_first.to_a).to eq([ newer, older ])
  end
end
