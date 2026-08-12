# frozen_string_literal: true

class Admin::DashboardsController < Admin::BaseController
  def show
    @stats = Documents::DashboardStatsService.call
  end
end
