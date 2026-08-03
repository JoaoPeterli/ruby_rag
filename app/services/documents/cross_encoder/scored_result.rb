# frozen_string_literal: true

module Documents
  module CrossEncoder
    ScoredResult = Data.define(
      :result,
      :cross_encoder_score,
      :cross_encoder_reason,
      :retrieval_score,
      :combined_score
    ) do
      def chunk
        result.chunk
      end
    end
  end
end
