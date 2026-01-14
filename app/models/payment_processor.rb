class PaymentProcessor < ApplicationRecord
  SYNC_STATUSES = %w[unknown healthy degraded failing disabled].freeze
  PROCESSOR_KEYS = %w[paypal recharge kofi].freeze

  validates :key, presence: true, uniqueness: true, inclusion: { in: PROCESSOR_KEYS }
  validates :name, presence: true
  validates :sync_status, inclusion: { in: SYNC_STATUSES }

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:display_order, :name) }
  scope :by_key, ->(key) { find_by(key: key) }

  # Find or create processor by key
  def self.for(key)
    find_or_create_by!(key: key) do |processor|
      processor.name = key.titleize
      processor.display_order = PROCESSOR_KEYS.index(key) || 99
    end
  end

  # Update statistics from payment records
  def refresh_statistics!
    payment_class = case key
                    when 'paypal' then PaypalPayment
                    when 'recharge' then RechargePayment
                    when 'kofi' then KofiPayment
                    end

    return unless payment_class

    total = payment_class.count
    matched = payment_class.where.not(user_id: nil).count
    unmatched = total - matched
    total_amt = payment_class.sum(:amount) || 0
    thirty_days_ago = 30.days.ago
    
    # Get the timestamp field name (varies by processor)
    time_field = case key
                 when 'paypal' then :transaction_time
                 when 'recharge' then :processed_at
                 when 'kofi' then :timestamp
                 end

    recent_amt = payment_class.where("#{time_field} >= ?", thirty_days_ago).sum(:amount) || 0
    avg_amt = total > 0 ? (total_amt / total) : 0

    update!(
      total_payments_count: total,
      matched_payments_count: matched,
      unmatched_payments_count: unmatched,
      total_amount: total_amt,
      amount_last_30_days: recent_amt,
      average_payment_amount: avg_amt
    )
  end

  # Record a successful sync
  def record_successful_sync!(count = nil)
    update!(
      last_sync_at: Time.current,
      last_successful_sync_at: Time.current,
      last_error_message: nil,
      consecutive_error_count: 0,
      sync_status: 'healthy'
    )
    refresh_statistics!
  end

  # Record a failed sync
  def record_failed_sync!(error_message)
    new_count = consecutive_error_count + 1
    status = new_count >= 3 ? 'failing' : 'degraded'

    update!(
      last_sync_at: Time.current,
      last_error_message: error_message.to_s.truncate(500),
      consecutive_error_count: new_count,
      sync_status: status
    )
  end

  # Record webhook received
  def record_webhook_received!
    update!(
      webhook_last_received_at: Time.current,
      webhook_configured: true
    )
  end

  # Record CSV import
  def record_csv_import!
    update!(
      last_csv_import_at: Time.current,
      csv_import_count: csv_import_count + 1
    )
    refresh_statistics!
  end

  # Check if API is configured based on environment variables
  def check_api_configuration!
    configured = case key
                 when 'paypal'
                   ENV['PAYPAL_CLIENT_ID'].present? && ENV['PAYPAL_CLIENT_SECRET'].present?
                 when 'recharge'
                   ENV['RECHARGE_API_KEY'].present?
                 when 'kofi'
                   ENV['KOFI_VERIFICATION_TOKEN'].present?
                 else
                   false
                 end

    update!(api_configured: configured)
  end

  # Human-readable status
  def status_label
    case sync_status
    when 'healthy' then 'Healthy'
    when 'degraded' then 'Degraded'
    when 'failing' then 'Failing'
    when 'disabled' then 'Disabled'
    else 'Unknown'
    end
  end

  # Status badge class for UI
  def status_badge_class
    case sync_status
    when 'healthy' then 'success'
    when 'degraded' then 'warning'
    when 'failing' then 'danger'
    when 'disabled' then 'secondary'
    else 'secondary'
    end
  end

  # Seed default processors
  def self.seed_defaults!
    [
      { key: 'paypal', name: 'PayPal', display_order: 1 },
      { key: 'recharge', name: 'Recharge', display_order: 2 },
      { key: 'kofi', name: 'Ko-Fi', display_order: 3 }
    ].each do |attrs|
      processor = find_or_initialize_by(key: attrs[:key])
      processor.assign_attributes(attrs)
      processor.save!
      processor.check_api_configuration!
      processor.refresh_statistics!
    end
  end
end
