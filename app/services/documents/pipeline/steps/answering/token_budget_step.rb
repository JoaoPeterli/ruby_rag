# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      module Answering
        class TokenBudgetStep < Documents::Pipeline::Step
          include LogsStageFailure

          def call
            return if context.result
            return unless context.config.token_budget_enabled

            context.token_budget = context.config.token_budget_service.call(
              total_budget: context.config.token_budget_total,
              response_reserve: context.config.token_budget_response_reserve,
              system_prompt_reserve: context.config.token_budget_system_prompt_reserve
            )
          rescue Documents::TokenBudgetService::Error => error
            log_stage_failure(stage: "token_budget", error: error)

            context.token_budget = nil
          end
        end
      end
    end
  end
end
