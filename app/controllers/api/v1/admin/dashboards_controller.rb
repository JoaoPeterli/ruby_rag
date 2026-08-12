# frozen_string_literal: true

module Api
  module V1
    module Admin
      class DashboardsController < BaseController
        def show
          stats = Documents::DashboardStatsService.call

          render json: {
            documents: stats.documents,
            queries: stats.queries,
            confidence: stats.confidence,
            feedback: stats.feedback,
            cost: stats.cost
          }
        end
      end
    end
  end
end
