# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Painel admin é operator-only: enxerga tudo, sem escopo por
      # conta (não existe visão "admin" escopada pro cliente).
      class BaseController < Api::V1::BaseController
        before_action :require_operator!

        private

        def require_operator!
          return if Current.account&.operator?

          render json: { error: "Não autorizado" }, status: :forbidden
        end
      end
    end
  end
end
