# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      module TracksStageFailures
        private

        def record_stage_failure(stage:, error:)
          context.metadata[:stage_failures] ||= []

          context.metadata[:stage_failures] << {
            stage: stage,
            error_class: error.class.name,
            error_message: error.message
          }
        end
      end
    end
  end
end
