# frozen_string_literal: true

# Irmão de ApplicationController (que é ActionController::API), não
# filho — a API sob api/v1/* não é afetada por nada daqui (sessão, CSRF,
# views). Mesma postura de segurança do Api::V1::Admin::BaseController
# (operator-only, sem escopo por conta), só que autenticado via sessão
# em vez de Bearer token.
class Admin::BaseController < ActionController::Base
  layout "admin"

  protect_from_forgery with: :exception

  before_action :require_operator!

  helper_method :current_account

  private

  def require_operator!
    return if current_account&.operator?

    redirect_to new_admin_session_path, alert: "Faça login com uma conta operadora."
  end

  def current_account
    return @current_account if defined?(@current_account)

    @current_account = Account.active.find_by(id: session[:account_id]).tap do |account|
      Current.account = account
    end
  end

  def record_audit_log(action:, target: nil, details: {})
    AdminAuditLog.create!(
      account: current_account,
      action: action,
      target_type: target&.class&.name,
      target_id: target&.id,
      details: details
    )
  end
end
