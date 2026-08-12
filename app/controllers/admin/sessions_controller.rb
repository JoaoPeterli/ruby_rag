# frozen_string_literal: true

class Admin::SessionsController < Admin::BaseController
  skip_before_action :require_operator!, only: [ :new, :create, :destroy ]

  rate_limit(
    to: 10,
    within: 3.minutes,
    only: :create,
    by: -> { request.remote_ip },
    with: -> {
      redirect_to new_admin_session_path,
                   alert: "Muitas tentativas de login. Tente novamente em alguns minutos."
    }
  )

  def new
    redirect_to admin_dashboard_path if current_account&.operator?
  end

  def create
    account = Account.active.find_by(api_key: params[:api_key].to_s.strip)

    unless account&.operator?
      flash.now[:alert] = "api_key inválida ou a conta não é operadora."
      render :new, status: :unprocessable_entity and return
    end

    session[:account_id] = account.id

    redirect_to admin_dashboard_path, notice: "Login realizado como #{account.name}."
  end

  def destroy
    session[:account_id] = nil

    redirect_to new_admin_session_path, notice: "Sessão encerrada."
  end
end
