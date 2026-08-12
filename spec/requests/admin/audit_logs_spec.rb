require "rails_helper"

RSpec.describe "Admin::AuditLogs", type: :request do
  let!(:operator) { create(:account, operator: true) }

  before { sign_in_as(operator) }

  it "redirects to login when there is no session" do
    delete admin_session_path

    get admin_audit_logs_path

    expect(response).to redirect_to(new_admin_session_path)
  end

  it "lists audit log entries, most recent first" do
    AdminAuditLog.create!(account: operator, action: "account.created", details: { name: "x" })

    get admin_audit_logs_path

    expect(response).to have_http_status(:success)
    assert_select "code", text: "account.created"
  end
end
