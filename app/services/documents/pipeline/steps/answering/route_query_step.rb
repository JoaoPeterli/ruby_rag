# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      module Answering
        class RouteQueryStep < Documents::Pipeline::Step
          include LogsStageFailure

          def call
            return if context.result
            return unless context.config.query_router_enabled

            context.route_query = context.config.query_router_service.call(
              question: context.effective_question
            )
          rescue Documents::QueryRouterService::Error => error
            log_stage_failure(stage: "query_router", error: error)

            context.route_query = nil
          end
        end
      end
    end
  end
end
