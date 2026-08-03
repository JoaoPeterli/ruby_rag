# frozen_string_literal: true

class RagRetrievalResult < ApplicationRecord
  belongs_to :rag_query
  belongs_to :document_chunk, optional: true
end
