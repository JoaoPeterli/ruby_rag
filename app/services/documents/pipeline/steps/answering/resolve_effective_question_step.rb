# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      module Answering
        class ResolveEffectiveQuestionStep < Documents::Pipeline::Step
          include LogsStageFailure

          def call
            context.query_rewrite_result = rewrite_question
            context.effective_question =
              context.query_rewrite_result&.rewritten_question ||
              context.normalized_question
          end

          private

          def rewrite_question
            return unless context.config.query_rewrite_enabled &&
                          context.conversation_history.present?

            context.config.query_rewrite_service.call(
              question: context.normalized_question,
              history: context.conversation_history
            )
          rescue Documents::QueryRewriteService::Error => error
            log_stage_failure(stage: "query_rewrite", error: error)

            nil
          end
        end
      end
    end
  end
end
