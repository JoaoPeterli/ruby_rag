# frozen_string_literal: true

module Documents
  module Evaluation
    Metrics = Data.define(
      :retrieval_precision,
      :retrieval_recall,
      :chunk_relevance,
      :answer_faithfulness,
      :citation_coverage,
      :no_evidence_correct
    )
  end
end
