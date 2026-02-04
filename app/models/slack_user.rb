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

  scope :active, -> { where(deleted: false, is_bot: false) }
  scope :with_attribute, ->(key, value) { where('raw_attributes ->> ? = ?', key.to_s, value.to_s) }

  # When a SlackUser is linked to a User, notify the User to sync data
  after_save :notify_user_of_link, if: :user_id_changed_to_present?

  def display_name
    display_name = self[:display_name].presence || real_name.presence || username.presence
    display_name || slack_id
  end

  private

  def user_id_changed_to_present?
    saved_change_to_user_id? && user_id.present?
  end

  def notify_user_of_link
    user.on_slack_user_linked(self)
  end
end
