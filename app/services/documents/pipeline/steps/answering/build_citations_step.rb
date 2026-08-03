# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      module Answering
        class BuildCitationsStep < Documents::Pipeline::Step
          include LogsStageFailure

          def call
            return if context.result
            return unless context.config.citation_engine_enabled

            context.citation_result = context.config.citation_engine.call(
              answer: context.chat_result.content,
              sources: context.context_result.sources
            )
          rescue Documents::CitationEngine::Service::Error => error
            log_stage_failure(stage: "citation_engine", error: error)

            context.citation_result = nil
          end
        end
      end
    end
  end
end
