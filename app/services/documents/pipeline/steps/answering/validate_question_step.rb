# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      module Answering
        class ValidateQuestionStep < Documents::Pipeline::Step
          def call
            unless context.question.is_a?(String) && context.question.strip.present?
              raise Documents::QuestionAnsweringService::InvalidQuestionError,
                    "A pergunta deve ser uma string não vazia"
            end

            context.normalized_question = context.question.strip
          end
        end
      end
    end
  end
end
