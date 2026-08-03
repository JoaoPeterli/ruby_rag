# frozen_string_literal: true

class RagEvalRun < ApplicationRecord
  has_many :rag_eval_results, dependent: :destroy
end
