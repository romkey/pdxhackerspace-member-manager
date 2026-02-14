# Manages incoming webhook endpoint configurations with dynamic URL slugs.
class IncomingWebhook < ApplicationRecord
  WEBHOOK_TYPES = %w[rfid kofi access authentik recharge].freeze
  SLUG_FORMAT = /\A[a-zA-Z0-9_-]+\z/

  validates :name, presence: true
  validates :webhook_type, presence: true, uniqueness: true, inclusion: { in: WEBHOOK_TYPES }
  validates :slug, presence: true, uniqueness: true,
                   format: { with: SLUG_FORMAT,
                             message: 'only allows letters, numbers, hyphens, and underscores' }

  scope :enabled, -> { where(enabled: true) }

  # Look up a webhook by its slug, only if enabled
  def self.find_enabled_by_slug(slug)
    enabled.find_by(slug: slug)
  end

  # Look up a webhook by its type
  def self.find_by_type(type)
    find_by(webhook_type: type)
  end

  # Generate a random slug (URL-safe, 24 characters)
  def self.generate_random_slug
    loop do
      slug = SecureRandom.urlsafe_base64(18) # 24 characters
      return slug unless exists?(slug: slug)
    end
  end

  # Regenerate the slug with either a custom value or a random one
  def regenerate_slug!(custom_slug = nil)
    new_slug = custom_slug.presence || self.class.generate_random_slug
    update!(slug: new_slug)
  end

  # Full webhook URL (requires MEMBER_MANAGER_BASE_URL to be set)
  def webhook_url
    base_url = ENV.fetch('MEMBER_MANAGER_BASE_URL', nil)
    return nil if base_url.blank?

    "#{base_url.delete_suffix('/')}/webhooks/#{slug}"
  end

  # The path portion of the webhook URL
  def webhook_path
    "/webhooks/#{slug}"
  end

  # Seed defaults for all webhook types
  def self.seed_defaults!
    default_webhooks.each { |attrs| seed_webhook(attrs) }
  end

  def self.default_webhooks
    [
      { webhook_type: 'rfid', name: 'RFID',
        description: 'Receives RFID keyfob scans from readers for member authentication and door access.' },
      { webhook_type: 'kofi', name: 'Ko-Fi',
        description: 'Receives payment notifications from Ko-Fi for donations, subscriptions, and shop orders.' },
      { webhook_type: 'access', name: 'Access Log',
        description: 'Receives access log lines from door controllers for real-time access tracking.' },
      { webhook_type: 'authentik', name: 'Authentik',
        description: 'Receives user and group change notifications from Authentik identity provider.' },
      { webhook_type: 'recharge', name: 'Recharge',
        description: 'Receives subscription lifecycle events (created, cancelled) from Recharge.' }
    ]
  end

  def self.seed_webhook(attrs)
    webhook = find_or_initialize_by(webhook_type: attrs[:webhook_type])
    return unless webhook.new_record?

    webhook.assign_attributes(attrs.merge(slug: attrs[:webhook_type]))
    webhook.save!
  end
end
