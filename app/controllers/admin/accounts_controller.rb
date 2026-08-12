# frozen_string_literal: true

class Admin::AccountsController < Admin::BaseController
  include Paginatable

  before_action :set_account, only: [ :show, :edit, :update, :destroy, :update_operator ]

  def index
    scope = Account.order(created_at: :desc)

    @total_count = scope.count
    @accounts = scope.limit(PER_PAGE).offset(page_offset)
  end

  def show
    @documents_count = @account.documents.count
    @queries_count = @account.rag_queries.count
  end

  def new
    @account = Account.new
  end

  def create
    @account = Account.new(account_params)

    if @account.save
      record_audit_log(action: "account.created", target: @account, details: { name: @account.name })
      redirect_to admin_account_path(@account), notice: "Conta criada."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @account.update(account_params)
      record_audit_log(
        action: "account.updated",
        target: @account,
        details: { changes: @account.previous_changes.except("updated_at") }
      )

      redirect_to admin_account_path(@account), notice: "Conta atualizada."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Promover/rebaixar operator é deliberadamente separado de #update: dá
  # acesso total ao painel admin, sem escopo por conta, então exige que
  # quem está fazendo a mudança confirme a própria api_key — uma sessão
  # sequestrada (ex.: cookie roubado) não basta pra se auto-promover ou
  # promover outra conta.
  def update_operator
    unless api_key_confirmed?
      redirect_to admin_account_path(@account), alert: "api_key de confirmação incorreta."
      return
    end

    new_operator_value = ActiveModel::Type::Boolean.new.cast(params[:operator])
    previous_value = @account.operator?

    @account.update!(operator: new_operator_value)

    record_audit_log(
      action: "account.operator_changed",
      target: @account,
      details: { from: previous_value, to: @account.operator? }
    )

    redirect_to admin_account_path(@account), notice: "Status de operador atualizado."
  end

  def destroy
    if @account == current_account
      redirect_to admin_accounts_path, alert: "Você não pode remover a própria conta."
      return
    end

    @account.destroy!

    record_audit_log(action: "account.destroyed", target: @account, details: { name: @account.name })

    redirect_to admin_accounts_path, notice: "Conta removida."
  end

  private

  def set_account
    @account = Account.find(params[:id])
  end

  def account_params
    # :operator nunca é aceito aqui — só via #update_operator, que exige
    # reautenticação.
    params.require(:account).permit(:name, :active)
  end

  def api_key_confirmed?
    ActiveSupport::SecurityUtils.secure_compare(
      current_account.api_key,
      params[:confirm_api_key].to_s
    )
  end
end
