# frozen_string_literal: true

# Cadastro aberto (self-serve): qualquer visitante cria a própria
# Account + o primeiro User dela (owner: true) sem ninguém do time da
# JLP no meio. Account#save cascata pro User associado via has_many
# autosave -- se qualquer um dos dois for inválido, nenhum dos dois
# persiste.
class Portal::RegistrationsController < Portal::BaseController
  skip_before_action :require_login!, only: [ :new, :create ]

  rate_limit(
    to: 5,
    within: 1.hour,
    only: :create,
    by: -> { request.remote_ip },
    with: -> {
      redirect_to new_portal_registration_path,
                   alert: "Muitas tentativas de cadastro. Tente novamente mais tarde."
    }
  )

  def new
    redirect_to(portal_dashboard_path) and return if current_user

    @account = Account.new
    @user = @account.users.new
  end

  def create
    redirect_to(portal_dashboard_path) and return if current_user

    @account = Account.new(name: params[:account_name])
    @user = @account.users.new(user_params.merge(owner: true))

    if @account.save
      session[:user_id] = @user.id
      redirect_to portal_dashboard_path, notice: "Conta criada. Bem-vindo(a)!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.permit(:email, :password, :password_confirmation)
  end
end
