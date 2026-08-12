# frozen_string_literal: true

# Irmão de Admin::BaseController: mesmo padrão de reabilitar
# sessão/views num app api_only, só que autentica por User (email +
# senha) em vez de Account (api_key), e é escopado por conta -- todo
# controller filho só pode enxergar dados de current_user.account.
class Portal::BaseController < ActionController::Base
  layout "portal"

  protect_from_forgery with: :exception

  before_action :require_login!

  helper_method :current_user

  private

  def require_login!
    return if current_user

    redirect_to new_portal_session_path, alert: "Faça login para continuar."
  end

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = User.active.find_by(id: session[:user_id]).tap do |user|
      Current.account = user&.account
    end
  end
end
