# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      module Answering
        class CalculateConfidenceStep < Documents::Pipeline::Step
          include LogsStageFailure

          def call
            return if context.result
            return unless context.config.confidence_score_enabled

            context.confidence_result = context.config.confidence_score_service.call(
              retrieval_result: context.retrieval_result,
              citation_result: context.citation_result,
              groundedness_result: context.groundedness_result,
              hallucination_result: context.hallucination_result
            )
          rescue Documents::ConfidenceScoreService::Error => error
            log_stage_failure(stage: "confidence_score", error: error)

            context.confidence_result = nil
          end
        end
      end
    end
  end
end
