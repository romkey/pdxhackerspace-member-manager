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
  scope :with_attribute, ->(key, value) { where("raw_attributes ->> ? = ?", key.to_s, value.to_s) }

  def display_name
    display_name = self[:display_name].presence || real_name.presence || username.presence
    display_name || slack_id
  end
end
