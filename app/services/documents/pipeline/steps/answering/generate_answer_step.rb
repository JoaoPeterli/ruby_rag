# frozen_string_literal: true

module Documents
  module Pipeline
    module Steps
      module Answering
        class GenerateAnswerStep < Documents::Pipeline::Step
          def call
            return if context.result

            context.chat_result =
              if context.on_delta
                context.config.chat_stream_service.call(
                  messages: context.prompt.messages,
                  model: Ai::Configuration.chat_model,
                  temperature: Ai::Configuration.chat_temperature,
                  max_completion_tokens: response_token_budget,
                  &context.on_delta
                )
              else
                context.config.chat_completion_service.call(
                  messages: context.prompt.messages,
                  model: Ai::Configuration.chat_model,
                  temperature: Ai::Configuration.chat_temperature,
                  max_completion_tokens: response_token_budget
                )
              end
          rescue Ai::ChatCompletionService::Error, Ai::ChatCompletionStreamService::Error => error
            raise Documents::QuestionAnsweringService::AnswerGenerationError,
                  "Não foi possível gerar a resposta: #{error.message}"
          end

          private

          def response_token_budget
            context.token_budget&.response_budget_tokens ||
              Ai::Configuration.chat_max_completion_tokens
          end
        end
      end
    end
  end
end
