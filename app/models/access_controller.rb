class AccessController < ApplicationRecord
  belongs_to :access_controller_type, optional: true
  has_many :access_controller_logs, dependent: :destroy

  SYNC_STATUSES = %w[unknown success failed syncing].freeze
  PING_STATUSES = %w[unknown success failed].freeze

  validates :name, presence: true, uniqueness: true
  validates :hostname, presence: true
  validates :sync_status, inclusion: { in: SYNC_STATUSES }

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:display_order, :name) }

  # Record a successful sync
  def record_sync_success!(message = nil)
    update!(
      last_sync_at: Time.current,
      sync_status: 'success'
    )
  end

  # Record a failed sync
  def record_sync_failure!(message)
    update!(
      last_sync_at: Time.current,
      sync_status: 'failed'
    )
  end

  # Mark as syncing (in progress)
  def mark_syncing!
    update!(sync_status: 'syncing')
  end

  # Human-readable sync status
  def status_label
    case sync_status
    when 'success' then 'Success'
    when 'failed' then 'Failed'
    when 'syncing' then 'Syncing...'
    else 'Unknown'
    end
  end

  # Status badge class for UI
  def status_badge_class
    case sync_status
    when 'success' then 'success'
    when 'failed' then 'danger'
    when 'syncing' then 'info'
    else 'secondary'
    end
  end

  # Whether this controller supports ping
  def supports_ping?
    Array(access_controller_type&.actions).map(&:to_s).include?('ping')
  end

  # Ping status helpers
  def ping_status_label
    case ping_status
    when 'success' then 'Online'
    when 'failed' then 'Offline'
    else 'Unknown'
    end
  end

  def ping_status_badge_class
    case ping_status
    when 'success' then 'success'
    when 'failed' then 'danger'
    else 'secondary'
    end
  end

  # Whether this controller supports backup
  def supports_backup?
    Array(access_controller_type&.actions).map(&:to_s).include?('backup')
  end

  # Backup status helpers
  def backup_status_label
    case backup_status
    when 'success' then 'Success'
    when 'failed' then 'Failed'
    else 'Unknown'
    end
  end

  def backup_status_badge_class
    case backup_status
    when 'success' then 'success'
    when 'failed' then 'danger'
    else 'secondary'
    end
  end

  def record_backup_result!(status)
    update!(
      backup_status: status,
      last_backup_at: Time.current
    )
  end

  # Parse environment_variables text field into a hash
  # Format: one KEY=VALUE per line, blank lines and comments (#) ignored
  def parsed_environment_variables
    return {} if environment_variables.blank?

    environment_variables.each_line.each_with_object({}) do |line, hash|
      line = line.strip
      next if line.blank? || line.start_with?('#')

      key, value = line.split('=', 2)
      next if key.blank?

      hash[key.strip] = (value || '').strip
    end
  end
end
