# frozen_string_literal: true

module Documents
  module CrossEncoder
    Result = Data.define(
      :results,
      :scores,
      :original_count,
      :evaluated_count,
      :reranked_count,
      :average_score,
      :duration_ms,
      :model,
      :strategy
    ) do
      def empty?
        results.empty?
      end
    end
  end
end
