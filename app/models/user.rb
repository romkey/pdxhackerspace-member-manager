class User < ApplicationRecord
  has_one :sheet_entry, dependent: :nullify
  has_one :slack_user, dependent: :nullify
  has_many :paypal_payments, dependent: :nullify
  has_many :recharge_payments, dependent: :nullify
  has_many :journals, dependent: :destroy
  has_many :access_logs, dependent: :nullify
  validates :authentik_id, presence: true, uniqueness: true
  validates :email,
            allow_blank: true,
            uniqueness: true,
            format: {
              with: URI::MailTo::EMAIL_REGEXP,
              allow_blank: true
            }
  validate :extra_emails_format

  scope :active, -> { where(active: true) }
  scope :with_attribute, ->(key, value) { where("authentik_attributes ->> ? = ?", key.to_s, value.to_s) }
  scope :ordered_by_display_name, lambda {
    order(
      Arel.sql("LOWER(COALESCE(NULLIF(full_name, ''), NULLIF(email, ''), authentik_id)) ASC"),
      :email,
      :authentik_id
    )
  }

  def display_name
    full_name.presence || email.presence || authentik_id
  end

  after_create_commit :journal_created!
  after_update_commit :journal_updated!

  private

  def journal_created!
    Journal.create!(
      user: self,
      actor_user: Current.user,
      action: "created",
      changes_json: saved_changes_to_json_hash,
      changed_at: Time.current
    )
  end

  def journal_updated!
    return if saved_changes.except("updated_at").empty?

    Journal.create!(
      user: self,
      actor_user: Current.user,
      action: "updated",
      changes_json: saved_changes_to_json_hash,
      changed_at: Time.current
    )
  end

  def saved_changes_to_json_hash
    # Convert saved_changes to a { attr => { from: old, to: new } } structure,
    # and filter out noisy attributes.
    filtered = saved_changes.except("updated_at", "created_at", "last_synced_at")
    Hash[
      filtered.map do |attr, (from, to)|
        [attr, { "from" => from, "to" => to }]
      end
    ]
  end

  def extra_emails_format
    return if extra_emails.blank?

    extra_emails.each do |email|
      unless email.match?(URI::MailTo::EMAIL_REGEXP)
        errors.add(:extra_emails, "contains invalid email: #{email}")
      end
    end
  end
end
