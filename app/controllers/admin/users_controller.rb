# frozen_string_literal: true

class Admin::UsersController < Admin::BaseController
  include Paginatable

  before_action :set_user, only: [ :show, :edit, :update, :destroy ]

  def index
    scope = User.includes(:account).order(created_at: :desc)

    @account_filter = params[:account_id].presence
    scope = scope.where(account_id: @account_filter) if @account_filter

    @total_count = scope.count
    @users = scope.limit(PER_PAGE).offset(page_offset)
  end

  def show; end

  def new
    @user = User.new(account_id: params[:account_id])
  end

  def create
    @user = User.new(user_params)

    if @user.save
      record_audit_log(action: "user.created", target: @user, details: { email: @user.email, account_id: @user.account_id })
      redirect_to admin_user_path(@user), notice: "Usuário criado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @user.update(user_params)
      record_audit_log(
        action: "user.updated",
        target: @user,
        details: { changes: @user.previous_changes.except("updated_at", "password_digest") }
      )

      redirect_to admin_user_path(@user), notice: "Usuário atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @user.destroy!

    record_audit_log(action: "user.destroyed", target: @user, details: { email: @user.email })

    redirect_to admin_users_path, notice: "Usuário removido."
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:account_id, :email, :active, :password, :password_confirmation)
  end
end
