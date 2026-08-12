# frozen_string_literal: true

class Portal::DashboardsController < Portal::BaseController
  def show
    @stats = Documents::DashboardStatsService.call(account: current_user.account)
  end
end
