class AccessControllerLog < ApplicationRecord
  belongs_to :access_controller

  STATUSES = %w[running success failed].freeze

  validates :action, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :ordered, -> { order(created_at: :desc) }
  scope :recent, ->(limit = 50) { ordered.limit(limit) }

  def running?
    status == 'running'
  end

  def success?
    status == 'success'
  end

  def failed?
    status == 'failed'
  end

  def status_badge_class
    case status
    when 'success' then 'success'
    when 'failed' then 'danger'
    when 'running' then 'warning'
    else 'secondary'
    end
  end

  def duration
    return nil if running?
    return nil unless created_at && updated_at

    (updated_at - created_at).round(2)
  end
end
