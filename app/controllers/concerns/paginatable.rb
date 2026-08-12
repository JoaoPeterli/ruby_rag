# frozen_string_literal: true

module Paginatable
  extend ActiveSupport::Concern

  PER_PAGE = 25

  included do
    helper_method :current_page, :total_pages
  end

  private

  def current_page
    [ params[:page].to_i, 1 ].max
  end

  def page_offset
    (current_page - 1) * PER_PAGE
  end

  def total_pages(total_count)
    (total_count / PER_PAGE.to_f).ceil
  end
end
