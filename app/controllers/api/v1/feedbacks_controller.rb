# frozen_string_literal: true

module Api
  module V1
    class FeedbacksController < BaseController
      def create
        feedback = Documents::RecordFeedbackService.call(
          rag_answer_id: params.require(:answer_id),
          rating: params.require(:rating),
          reason: params[:reason],
          account_id: Current.account.id
        )

        render json: serialize(feedback), status: :created
      rescue Documents::RecordFeedbackService::Error => error
        render json: { error: error.message }, status: :unprocessable_entity
      end

      private

      def serialize(feedback)
        {
          id: feedback.id,
          rag_answer_id: feedback.rag_answer_id,
          rating: feedback.rating,
          reason: feedback.reason,
          created_at: feedback.created_at
        }
      end
    end
  end
end
