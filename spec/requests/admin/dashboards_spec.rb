require "rails_helper"

RSpec.describe "Admin::Dashboards", type: :request do
  it "redirects to login when there is no session" do
    get admin_dashboard_path

    expect(response).to redirect_to(new_admin_session_path)
  end

  it "renders the dashboard for a logged-in operator" do
    operator = create(:account, operator: true)
    sign_in_as(operator)

    get admin_dashboard_path

    expect(response).to have_http_status(:success)
  end
end
