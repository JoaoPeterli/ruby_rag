# frozen_string_literal: true

module Documents
  module PipelineObservability
    Report = Data.define(
      :stage_metrics,
      :stage_failures,
      :candidate_counts,
      :token_usage,
      :cost,
      :retrieval_duration_ms,
      :total_duration_ms
    )
  end
end
