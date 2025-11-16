class RechargePayment < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :sheet_entry, optional: true

  validates :recharge_id, presence: true, uniqueness: true

  scope :ordered, -> { order(processed_at: :desc, created_at: :desc) }
  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :for_sheet_entry, ->(entry) { where(sheet_entry_id: entry.id) }

  before_validation :normalize_email

  def amount_with_currency
    return nil if amount.blank?

    "#{format('%.2f', amount)} #{currency}"
  end

  def identifier
    recharge_id
  end

  def processed_time
    processed_at
  end

  private

  def normalize_email
    self.customer_email = customer_email.to_s.strip.downcase.presence
  end
end

