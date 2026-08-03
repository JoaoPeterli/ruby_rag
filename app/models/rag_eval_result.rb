# frozen_string_literal: true

class RagEvalResult < ApplicationRecord
  belongs_to :rag_eval_run
  belongs_to :rag_eval_case
end
