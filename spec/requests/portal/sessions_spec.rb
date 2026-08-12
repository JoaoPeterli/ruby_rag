require "rails_helper"

RSpec.describe "Portal::Sessions", type: :request do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account, password: "senha1234") }

  it "logs in a user with valid credentials" do
    post portal_session_path, params: { email: user.email, password: "senha1234" }

    expect(response).to redirect_to(portal_dashboard_path)
    follow_redirect!
    expect(response).to have_http_status(:success)
  end

  it "rejects an invalid password" do
    post portal_session_path, params: { email: user.email, password: "senha-errada" }

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "rejects an unknown email" do
    post portal_session_path, params: { email: "ninguem@teste.com", password: "senha1234" }

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "rejects an inactive user" do
    user.update!(active: false)

    post portal_session_path, params: { email: user.email, password: "senha1234" }

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "logs out and blocks further access to the portal" do
    sign_in_as_user(user)

    delete portal_session_path
    expect(response).to redirect_to(new_portal_session_path)

    get portal_dashboard_path
    expect(response).to redirect_to(new_portal_session_path)
  end
end
