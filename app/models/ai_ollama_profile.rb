class AiOllamaProfile < ApplicationRecord
  EMAIL_REWRITING_DEFAULT_PROMPT = <<~PROMPT.freeze
    You rewrite outbound emails for clarity, warmth, and professionalism.
    Keep the original intent, factual details, and calls to action.
    Preserve all links, placeholders, and template variables exactly as provided.
    Return polished copy that is concise and easy to read.
  PROMPT

  KEYS = %w[default application_status recommendation_engine email_rewriting].freeze
  HEALTH_STATUSES = %w[unknown healthy unhealthy not_configured].freeze

  validates :key, presence: true, uniqueness: true, inclusion: { in: KEYS }
  validates :name, presence: true
  validates :health_status, inclusion: { in: HEALTH_STATUSES }

  scope :ordered, -> { order(:display_order, :id) }

  def self.default_profile
    find_by(key: 'default')
  end

  def self.seed_defaults!
    [
      { key: 'default', name: 'Default', display_order: 0 },
      { key: 'application_status', name: 'Application Status', display_order: 1 },
      { key: 'recommendation_engine', name: 'Recommendation Engine', display_order: 2 },
      {
        key: 'email_rewriting',
        name: 'Email Rewriting',
        display_order: 3,
        prompt: EMAIL_REWRITING_DEFAULT_PROMPT
      }
    ].each do |attrs|
      find_or_initialize_by(key: attrs[:key]).tap do |row|
        row.name = attrs[:name]
        row.display_order = attrs[:display_order]
        row.prompt = attrs[:prompt] if row.prompt.to_s.strip.blank? && attrs[:prompt].present?
        row.enabled = true if row.enabled.nil?
        row.health_status = 'not_configured' if row.new_record?
        row.save!
      end
    end
  end

  # Resolved Ollama base URL: own base_url, or the Default profile's when blank (non-default rows only).
  def effective_base_url
    raw = base_url.to_s.strip
    return raw if raw.present?
    return '' if key == 'default'

    self.class.default_profile&.base_url.to_s.strip
  end

  # Resolved model name: own model, or the Default profile's when blank (non-default rows only).
  def effective_model
    raw = model.to_s.strip
    return raw if raw.present?
    return '' if key == 'default'

    self.class.default_profile&.model.to_s.strip
  end

  def urgent_health_issue?
    enabled? && effective_base_url.present? && health_status == 'unhealthy'
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

  def record_not_configured!
    update!(
      health_status: 'not_configured',
      last_health_check_at: Time.current,
      last_health_error: nil
    )
  end

  def health_status_label
    return 'Disabled' unless enabled?

    case health_status
    when 'healthy' then 'Healthy'
    when 'unhealthy' then 'Unhealthy'
    when 'not_configured' then 'Unconfigured'
    else 'Unknown'
    end
  end

  def health_status_badge_class
    return 'secondary' unless enabled?

    case health_status
    when 'healthy' then 'success'
    when 'unhealthy' then 'danger'
    when 'not_configured' then 'warning'
    else 'secondary'
    end
  end
end
