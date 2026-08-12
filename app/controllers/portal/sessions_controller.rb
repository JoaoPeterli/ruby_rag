# frozen_string_literal: true

class Portal::SessionsController < Portal::BaseController
  skip_before_action :require_login!, only: [ :new, :create, :destroy ]

  rate_limit(
    to: 10,
    within: 3.minutes,
    only: :create,
    by: -> { request.remote_ip },
    with: -> {
      redirect_to new_portal_session_path,
                   alert: "Muitas tentativas de login. Tente novamente em alguns minutos."
    }
  )

  def new
    redirect_to portal_dashboard_path if current_user
  end

  def create
    user = User.active.find_by(email: params[:email].to_s.strip.downcase)

    unless user&.authenticate(params[:password].to_s)
      flash.now[:alert] = "email ou senha inválidos."
      render :new, status: :unprocessable_entity and return
    end

    session[:user_id] = user.id

    redirect_to portal_dashboard_path, notice: "Login realizado como #{user.email}."
  end

  def destroy
    session[:user_id] = nil

    redirect_to new_portal_session_path, notice: "Sessão encerrada."
  end
end
