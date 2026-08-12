# frozen_string_literal: true

class Admin::AuditLogsController < Admin::BaseController
  include Paginatable

  def index
    scope = AdminAuditLog.includes(:account).recent_first

    @total_count = scope.count
    @logs = scope.limit(PER_PAGE).offset(page_offset)
  end
end
