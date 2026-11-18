require "rails_helper"

RSpec.describe "Portal::Registrations", type: :request do
  it "creates an account and an owner user, then logs them in" do
    expect do
      post portal_registration_path, params: {
        account_name: "Corretora Nova",
        email: "dono@corretora-nova.com",
        password: "senha1234",
        password_confirmation: "senha1234"
      }
    end.to change(Account, :count).by(1).and change(User, :count).by(1)

    expect(response).to redirect_to(portal_dashboard_path)

    account = Account.order(:created_at).last
    user = User.order(:created_at).last

    expect(account.name).to eq("Corretora Nova")
    expect(account.operator?).to be_falsey
    expect(user.account_id).to eq(account.id)
    expect(user.owner?).to be_truthy

    follow_redirect!
    expect(response).to have_http_status(:success)
  end

  it "rolls back both records when the user is invalid" do
    expect do
      post portal_registration_path, params: {
        account_name: "Corretora Inválida",
        email: "nao-e-email",
        password: "senha1234",
        password_confirmation: "senha1234"
      }
    end.to change(Account, :count).by(0).and change(User, :count).by(0)

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "requires a company name" do
    expect do
      post portal_registration_path, params: {
        account_name: "",
        email: "dono@corretora.com",
        password: "senha1234",
        password_confirmation: "senha1234"
      }
    end.to change(Account, :count).by(0)

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "redirects an already logged-in user straight to the dashboard" do
    user = create(:user, password: "senha1234")
    sign_in_as_user(user)

    get new_portal_registration_path

    expect(response).to redirect_to(portal_dashboard_path)
  end
end
