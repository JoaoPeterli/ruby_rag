# frozen_string_literal: true

module Api
  module V1
    class QuestionsController < BaseController
      include ActionController::Live

      MAX_QUESTION_LENGTH = 2_000

      rate_limit(
        to: 20,
        within: 1.minute,
        by: -> { request.remote_ip },
        with: -> {
          render json: { error: "Limite de requisições excedido" },
                 status: :too_many_requests
        }
      )

      def create
        question = params.require(:question)

        return render_question_too_long unless valid_question_length?(question)

        result = Documents::QuestionAnsweringService.call(
          question: question,
          account_id: Current.account.id,
          conversation_history: conversation_history_param
        )

        render json: Documents::QuestionAnsweringResultSerializer.call(result: result)
      rescue Documents::QuestionAnsweringService::Error => error
        render json: { error: error.message }, status: :unprocessable_entity
      end

      # SSE: event "delta" a cada pedaço de texto, "done" no final com o
      # resultado completo (fontes, citações, confiança), "error" se
      # algo falhar depois que o stream já começou (nesse ponto não dá
      # mais pra trocar o status HTTP, só comunicar via corpo do evento).
      def stream
        question = params.require(:question)

        return render_question_too_long unless valid_question_length?(question)

        response.headers["Content-Type"] = "text/event-stream"
        response.headers["Cache-Control"] = "no-cache"
        response.headers["X-Accel-Buffering"] = "no"

        result = Documents::QuestionAnsweringService.call(
          question: question,
          account_id: Current.account.id,
          conversation_history: conversation_history_param
        ) do |delta|
          write_sse(event: "delta", data: { content: delta })
        end

        write_sse(
          event: "done",
          data: Documents::QuestionAnsweringResultSerializer.call(result: result)
        )
      rescue Documents::QuestionAnsweringService::Error => error
        write_sse(event: "error", data: { error: error.message })
      ensure
        response.stream.close
      end

      private

      def valid_question_length?(question)
        question.to_s.length <= MAX_QUESTION_LENGTH
      end

      def render_question_too_long
        render(
          json: {
            error: "A pergunta é longa demais " \
                   "(máximo #{MAX_QUESTION_LENGTH} caracteres)"
          },
          status: :unprocessable_entity
        )
      end

      def write_sse(event:, data:)
        response.stream.write("event: #{event}\n")
        response.stream.write("data: #{data.to_json}\n\n")
      end

      def conversation_history_param
        Array(params[:conversation_history]).map do |turn|
          {
            role: turn[:role] || turn["role"],
            content: turn[:content] || turn["content"]
          }
        end
      end
    end
  end
end
