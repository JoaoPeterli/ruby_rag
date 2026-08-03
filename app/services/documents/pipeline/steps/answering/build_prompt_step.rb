# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      module Answering
        class BuildPromptStep < Documents::Pipeline::Step
          def call
            return if context.result

            context.prompt = context.config.prompt_builder.call(
              question: context.effective_question,
              context_result: context.context_result,
              conversation_history: context.conversation_history
            )
          rescue Documents::PromptBuilder::Error => error
            raise Documents::QuestionAnsweringService::PromptBuildError,
                  "Não foi possível construir o prompt: #{error.message}"
          end
        end
      end
    end
  end
end
