# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      module Answering
        module LogsStageFailure
          private

          def log_stage_failure(stage:, error:)
            Rails.logger.warn(
              event: "document_question_answering_stage_failure",
              stage: stage,
              error_class: error.class.name,
              error_message: error.message
            )
          end
        end
      end
    end
  end
end
