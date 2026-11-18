require "rails_helper"

RSpec.describe "Portal::Users", type: :request do
  let!(:account) { create(:account) }
  let!(:owner) { create(:user, account: account, owner: true, password: "senha1234") }

  it "requires login" do
    get portal_users_path

    expect(response).to redirect_to(new_portal_session_path)
  end

  it "blocks a non-owner from managing the team" do
    member = create(:user, account: account, owner: false, password: "senha1234")
    sign_in_as_user(member)

    get portal_users_path

    expect(response).to redirect_to(portal_dashboard_path)
  end

  it "lets the owner list teammates scoped to their own account" do
    teammate = create(:user, account: account, password: "senha1234")
    create(:user, password: "senha1234") # outra conta, não deve aparecer

    sign_in_as_user(owner)
    get portal_users_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include(teammate.email)
  end

  it "invites a teammate with a generated password and shows it once" do
    sign_in_as_user(owner)

    expect do
      post portal_users_path, params: { email: "novo@teste.com" }
    end.to change { account.users.count }.by(1)

    invited = account.users.find_by(email: "novo@teste.com")
    expect(invited.owner?).to be_falsey
    expect(invited.authenticate(flash[:generated_password])).to be_truthy
  end

  it "does not let the owner invite into someone else's account" do
    other_account = create(:account)

    sign_in_as_user(owner)
    post portal_users_path, params: { email: "novo@teste.com" }

    expect(other_account.users.where(email: "novo@teste.com")).to be_empty
  end

  it "toggles a teammate's active status" do
    teammate = create(:user, account: account, active: true, password: "senha1234")
    sign_in_as_user(owner)

    patch portal_user_path(teammate), params: { active: "false" }

    expect(teammate.reload.active?).to be_falsey
  end

  it "refuses to let the owner deactivate themselves" do
    sign_in_as_user(owner)

    patch portal_user_path(owner), params: { active: "false" }

    expect(owner.reload.active?).to be_truthy
    expect(response).to redirect_to(portal_users_path)
  end

  it "does not let the owner touch a user from another account" do
    outsider = create(:user, password: "senha1234")
    sign_in_as_user(owner)

    patch portal_user_path(outsider), params: { active: "false" }

    expect(response).to have_http_status(:not_found)
    expect(outsider.reload.active?).to be_truthy
  end
end
