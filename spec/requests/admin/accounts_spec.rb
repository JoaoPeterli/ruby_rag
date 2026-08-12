require "rails_helper"

RSpec.describe "Admin::Accounts", type: :request do
  let!(:operator) { create(:account, operator: true) }

  before { sign_in_as(operator) }

  it "redirects to login when there is no session" do
    delete admin_session_path

    get admin_accounts_path

    expect(response).to redirect_to(new_admin_session_path)
  end

  it "creates a new account with an auto-generated api_key" do
    expect do
      post admin_accounts_path, params: { account: { name: "Nova Conta", operator: false } }
    end.to change(Account, :count).by(1)

    account = Account.order(:created_at).last
    expect(response).to redirect_to(admin_account_path(account))
    expect(account.api_key).to be_present
    expect(account.operator?).to be_falsey

    log = AdminAuditLog.order(:created_at).last
    expect(log.action).to eq("account.created")
  end

  it "update does not accept operator through the general edit form" do
    account = create(:account, name: "Não vira Operador")

    patch admin_account_path(account), params: { account: { name: account.name, active: true, operator: true } }

    expect(response).to redirect_to(admin_account_path(account))
    expect(account.reload.operator?).to be_falsey
  end

  it "promotes an account to operator when the confirm_api_key matches the current session" do
    account = create(:account, name: "Vira Operador")

    patch update_operator_admin_account_path(account),
          params: { operator: "true", confirm_api_key: operator.api_key }

    expect(response).to redirect_to(admin_account_path(account))
    expect(account.reload.operator?).to be_truthy

    log = AdminAuditLog.order(:created_at).last
    expect(log.action).to eq("account.operator_changed")
    expect(log.account_id).to eq(operator.id)
  end

  it "refuses to change operator status when confirm_api_key is wrong" do
    account = create(:account, name: "Continua Não-Operador")

    patch update_operator_admin_account_path(account),
          params: { operator: "true", confirm_api_key: "chave-errada" }

    expect(response).to redirect_to(admin_account_path(account))
    expect(account.reload.operator?).to be_falsey
  end

  it "demotes an operator account with confirmation" do
    account = create(:account, name: "Vai Perder Operator", operator: true)

    patch update_operator_admin_account_path(account),
          params: { operator: "false", confirm_api_key: operator.api_key }

    expect(account.reload.operator?).to be_falsey
  end

  it "prevents an account from deleting itself" do
    expect do
      delete admin_account_path(operator)
    end.not_to change(Account, :count)

    expect(response).to redirect_to(admin_accounts_path)
    expect(Account.exists?(operator.id)).to be_truthy
  end

  it "destroys another account" do
    account = create(:account, name: "Descartável")

    expect do
      delete admin_account_path(account)
    end.to change(Account, :count).by(-1)

    log = AdminAuditLog.order(:created_at).last
    expect(log.action).to eq("account.destroyed")
    expect(log.target_id).to eq(account.id)
  end
end
