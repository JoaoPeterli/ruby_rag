# frozen_string_literal: true

# Gestão de time, restrita ao "owner" da conta (quem se cadastrou --
# ver Portal::RegistrationsController). Sem envio de email nesta
# rodada: a senha do convidado é gerada aqui e mostrada uma única vez
# (via flash), pro owner copiar e repassar por fora.
class Portal::UsersController < Portal::BaseController
  before_action :require_owner!

  def index
    @teammates = current_user.account.users.order(:email)
  end

  def create
    generated_password = SecureRandom.hex(6)

    @user = current_user.account.users.new(
      email: params[:email],
      password: generated_password,
      password_confirmation: generated_password,
      owner: false
    )

    if @user.save
      flash[:generated_password] = generated_password
      flash[:generated_password_email] = @user.email
      redirect_to portal_users_path, notice: "Usuário convidado."
    else
      @teammates = current_user.account.users.order(:email)
      flash.now[:alert] = @user.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def update
    teammate = current_user.account.users.find(params[:id])

    if teammate == current_user
      redirect_to portal_users_path, alert: "Você não pode desativar a si mesmo."
      return
    end

    teammate.update!(active: ActiveModel::Type::Boolean.new.cast(params[:active]))

    redirect_to portal_users_path, notice: "Usuário atualizado."
  end

  private

  def require_owner!
    return if current_user.owner?

    redirect_to portal_dashboard_path, alert: "Só o dono da conta pode gerenciar usuários."
  end
end
