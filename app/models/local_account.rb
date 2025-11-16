class LocalAccount < ApplicationRecord
  has_secure_password

  validates :email, presence: true, uniqueness: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 12 }, allow_nil: true
  validates :password_digest, presence: true

  scope :active, -> { where(active: true) }

  def display_name
    full_name.presence || email
  end
end
