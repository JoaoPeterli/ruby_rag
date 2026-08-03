# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      module Answering
        class AdaptiveRetrievalPlanStep < Documents::Pipeline::Step
          include LogsStageFailure

          def call
            return if context.result
            return unless context.config.adaptive_retrieval_enabled

            context.adaptive_plan = context.config.adaptive_retrieval_planner.call(
              question: context.effective_question,
              category: context.route_query&.category
            )
          rescue Documents::AdaptiveRetrievalPlanner::Error => error
            log_stage_failure(stage: "adaptive_retrieval_planner", error: error)

            context.adaptive_plan = nil
          end
        end
      end
    end
  end
end
