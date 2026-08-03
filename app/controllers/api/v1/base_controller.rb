# frozen_string_literal: true

module Api
  module V1
    # Autenticação por api_key de Account (aulas 45-46). Cada request
    # autenticado carrega Current.account pro resto da stack — os
    # controllers passam account_id: explicitamente pros services, o
    # que garante que o "account_id: nil = sem restrição" default nas
    # camadas internas nunca é alcançável a partir de uma requisição
    # HTTP de verdade.
    class BaseController < ApplicationController
      before_action :authenticate!

      # rescue_from casa na ordem inversa de declaração (o último
      # registrado é checado primeiro), então o StandardError genérico
      # precisa vir ANTES dos mais específicos — senão ele intercepta
      # tudo, inclusive ParameterMissing/RecordNotFound.
      rescue_from StandardError, with: :render_internal_error
      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
      rescue_from ActionController::ParameterMissing, with: :render_missing_parameter

      private

      def authenticate!
        account = Account.active.find_by(api_key: provided_token)

        return render json: { error: "Não autorizado" }, status: :unauthorized if account.nil?

        Current.account = account
      end

      def provided_token
        request.headers["Authorization"].to_s.sub(/\ABearer\s+/i, "")
      end

      def render_not_found
        render json: { error: "Não encontrado" }, status: :not_found
      end

      def render_missing_parameter(error)
        render json: { error: error.message }, status: :unprocessable_entity
      end

      def render_internal_error(error)
        Rails.logger.error(
          event: "api_internal_error",
          error_class: error.class.name,
          error_message: error.message
        )

        render json: { error: "Erro interno" }, status: :internal_server_error
      end
    end
  end
end
