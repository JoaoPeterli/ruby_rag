# frozen_string_literal: true

class Admin::DocumentsController < Admin::BaseController
  include Paginatable

  def index
    scope = Document.order(created_at: :desc)

    @status_filter = params[:status]
    scope = scope.where(status: @status_filter) if @status_filter.present?

    @total_count = scope.count
    @documents = scope.limit(PER_PAGE).offset(page_offset)
  end

  def show
    @document = Document.find(params[:id])
    @chunks = @document.document_chunks.ordered
  end
end
