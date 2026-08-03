# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      module Answering
        class CheckHallucinationStep < Documents::Pipeline::Step
          include LogsStageFailure

          def call
            return if context.result
            return unless context.config.hallucination_check_enabled

            context.hallucination_result = context.config.hallucination_check_service.call(
              question: context.effective_question,
              answer: context.chat_result.content,
              context: context.context_result.context
            )
          rescue Documents::HallucinationCheckService::Error => error
            log_stage_failure(stage: "hallucination_check", error: error)

            context.hallucination_result = nil
          end
        end
      end
    end
  end
end
