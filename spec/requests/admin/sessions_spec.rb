require "rails_helper"

RSpec.describe "Admin::Sessions", type: :request do
  let!(:operator) { create(:account, operator: true) }
  let!(:regular) { create(:account, operator: false) }

  it "logs in an operator account with a valid api_key" do
    post admin_session_path, params: { api_key: operator.api_key }

    expect(response).to redirect_to(admin_dashboard_path)
    follow_redirect!
    expect(response).to have_http_status(:success)
  end

  it "rejects a non-operator account" do
    post admin_session_path, params: { api_key: regular.api_key }

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "rejects an invalid api_key" do
    post admin_session_path, params: { api_key: "chave-invalida" }

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "logs out and blocks further access to the admin area" do
    sign_in_as(operator)

    delete admin_session_path
    expect(response).to redirect_to(new_admin_session_path)

    get admin_dashboard_path
    expect(response).to redirect_to(new_admin_session_path)
  end
end
