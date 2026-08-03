# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      module Answering
        class BuildResultStep < Documents::Pipeline::Step
          def call
            return if context.result

            context.result = Documents::QuestionAnsweringService::ResultBuilder.success(
              context: context,
              chat_result: context.chat_result,
              retrieval_result: context.retrieval_result,
              citation_result: context.citation_result,
              groundedness_result: context.groundedness_result,
              hallucination_result: context.hallucination_result,
              confidence_result: context.confidence_result
            )
          end
        end
      end
    end
  end
end
