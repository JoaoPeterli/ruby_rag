# frozen_string_literal: true

class Admin::QueriesController < Admin::BaseController
  include Paginatable

  def index
    scope = RagQuery.includes(:rag_answer).order(created_at: :desc)

    @total_count = scope.count
    @queries = scope.limit(PER_PAGE).offset(page_offset)
  end

  def show
    @query = RagQuery.includes(:rag_answer, rag_retrieval_results: :document_chunk).find(params[:id])
  end
end
