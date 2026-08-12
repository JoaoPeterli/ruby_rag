# frozen_string_literal: true

module StatusBadgeHelper
  STATUS_BADGE_CLASSES = {
    "completed" => "bg-success-lt",
    "failed" => "bg-danger-lt",
    "processing" => "bg-warning-lt",
    "queued" => "bg-warning-lt",
    "pending" => "bg-warning-lt",
    "uploaded" => "bg-secondary-lt"
  }.freeze

  def status_badge_class(status)
    STATUS_BADGE_CLASSES.fetch(status.to_s, "bg-secondary-lt")
  end
end
