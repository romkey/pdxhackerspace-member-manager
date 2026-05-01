class SlackUser < ApplicationRecord
  belongs_to :user, optional: true
  validates :slack_id, presence: true, uniqueness: true
  validates :email,
            allow_blank: true,
            uniqueness: true,
            format: {
              with: URI::MailTo::EMAIL_REGEXP,
              allow_blank: true
            }

  ACTIVE_WINDOW = 1.year

  scope :human, -> { where(is_bot: false) }
  scope :deactivated, -> { where(deleted: true) }
  scope :not_deactivated, -> { where(deleted: false) }
  scope :inactive, lambda {
    not_deactivated.where('last_active_at < ? OR last_active_at IS NULL', inactive_cutoff)
  }
  scope :active, -> { not_deactivated.where(last_active_at: inactive_cutoff..) }
  scope :with_attribute, ->(key, value) { where('raw_attributes ->> ? = ?', key.to_s, value.to_s) }

  def display_name
    display_name = self[:display_name].presence || real_name.presence || username.presence
    display_name || slack_id
  end

  def self.inactive_cutoff
    ACTIVE_WINDOW.ago
  end

  def inactive?
    !deleted? && (last_active_at.blank? || last_active_at < self.class.inactive_cutoff)
  end

  def active?
    !deleted? && !inactive?
  end

  private

  def user_id_changed_to_present?
    saved_change_to_user_id? && user_id.present?
  end

  def notify_user_of_link
    user.on_slack_user_linked(self)
  end
end
