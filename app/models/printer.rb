class Printer < ApplicationRecord
  HEALTH_STATUSES = %w[unknown healthy unhealthy].freeze

  before_validation :normalize_cups_printer_server

  validates :name, presence: true, uniqueness: true
  validates :cups_printer_name, presence: true, uniqueness: { scope: :cups_printer_server }
  validates :health_status, inclusion: { in: HEALTH_STATUSES }

  scope :ordered, -> { order(:position, :name) }
  scope :default_printer, -> { where(default_printer: true) }
  scope :unhealthy, -> { where(health_status: 'unhealthy') }

  before_save :ensure_single_default

  def to_s
    name
  end

  def self.default
    default_printer.first || ordered.first
  end

  def cups_destination
    return cups_printer_name if cups_printer_server.blank?

    "#{cups_printer_server}/#{cups_printer_name}"
  end

  def urgent_health_issue?
    health_status == 'unhealthy'
  end

  def record_health_success!
    update!(
      health_status: 'healthy',
      last_health_check_at: Time.current,
      last_health_error: nil
    )
  end

  def record_health_failure!(message)
    update!(
      health_status: 'unhealthy',
      last_health_check_at: Time.current,
      last_health_error: message.to_s.truncate(500)
    )
  end

  def health_status_label
    case health_status
    when 'healthy' then 'Healthy'
    when 'unhealthy' then 'Unhealthy'
    else 'Unknown'
    end
  end

  def health_status_badge_class
    case health_status
    when 'healthy' then 'success'
    when 'unhealthy' then 'danger'
    else 'secondary'
    end
  end

  private

  def normalize_cups_printer_server
    self.cups_printer_server = cups_printer_server.to_s.strip
  end

  def ensure_single_default
    return unless default_printer? && default_printer_changed?

    Printer.where.not(id: id).update_all(default_printer: false)
  end
end
