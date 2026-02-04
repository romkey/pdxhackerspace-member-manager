class PaypalPayment < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :sheet_entry, optional: true

  validates :paypal_id, presence: true, uniqueness: true

  scope :ordered, -> { order(transaction_time: :desc, created_at: :desc) }
  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :for_sheet_entry, ->(entry) { where(sheet_entry_id: entry.id) }

  before_validation :normalize_payer_email

  # When a PaypalPayment is linked to a User, notify the User to sync data
  after_save :notify_user_of_link, if: :user_id_changed_to_present?

  def amount_with_currency
    return nil if amount.blank?

    "#{format('%.2f', amount)} #{currency}"
  end

  def identifier
    paypal_id
  end

  def processed_time
    transaction_time
  end

  private

  def normalize_payer_email
    self.payer_email = payer_email.to_s.strip.downcase.presence
  end

  def user_id_changed_to_present?
    saved_change_to_user_id? && user_id.present?
  end

  def notify_user_of_link
    user.on_paypal_payment_linked(self)
  end
end
