# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      module Answering
        class CheckGroundednessStep < Documents::Pipeline::Step
          include LogsStageFailure

          def call
            return if context.result
            return unless context.config.groundedness_check_enabled

            context.groundedness_result = context.config.groundedness_check_service.call(
              answer: context.chat_result.content,
              citation_count: context.citation_result&.citation_count || 0
            )
          rescue Documents::GroundednessCheckService::Error => error
            log_stage_failure(stage: "groundedness_check", error: error)

            context.groundedness_result = nil
          end
        end
      end
    end
  end
end
