require "rails_helper"

RSpec.describe "Portal::Dashboards", type: :request do
  it "redirects to portal login when there is no session" do
    get portal_dashboard_path

    expect(response).to redirect_to(new_portal_session_path)
  end

  it "renders the dashboard for a logged-in user" do
    user = create(:user, password: "senha1234")
    sign_in_as_user(user)

    get portal_dashboard_path

    expect(response).to have_http_status(:success)
  end

  describe "root path" do
    it "redirects to portal login when there is no session" do
      get root_path

      expect(response).to redirect_to(new_portal_session_path)
    end

    it "renders the portal dashboard for a logged-in user (root is customer-facing, not admin)" do
      user = create(:user, password: "senha1234")
      sign_in_as_user(user)

      get root_path

      expect(response).to have_http_status(:success)
    end
  end
end
