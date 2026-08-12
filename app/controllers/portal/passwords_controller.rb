# frozen_string_literal: true

# Troca de senha autenticada (exige a senha atual). Não existe fluxo
# de "esqueci minha senha" por email nesta rodada -- exigiria
# configurar ActionMailer/SMTP, que o projeto ainda não tem.
class Portal::PasswordsController < Portal::BaseController
  def edit
  end

  def update
    unless current_user.authenticate(params[:current_password].to_s)
      flash.now[:alert] = "Senha atual incorreta."
      render :edit, status: :unprocessable_entity and return
    end

    if current_user.update(password: params[:password], password_confirmation: params[:password_confirmation])
      redirect_to portal_dashboard_path, notice: "Senha alterada com sucesso."
    else
      flash.now[:alert] = current_user.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end
end
