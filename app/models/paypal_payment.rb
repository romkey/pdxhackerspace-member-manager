class PaypalPayment < ApplicationRecord
  include NormalizesEmail

  normalizes_email_field :payer_email

  belongs_to :user, optional: true
  has_many :payment_events, dependent: :nullify

  validates :paypal_id, presence: true, uniqueness: true

  scope :ordered, -> { order(transaction_time: :desc, created_at: :desc) }
  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :matching_plan, -> { where(matches_plan: true) }
  scope :not_matching_plan, -> { where(matches_plan: false) }
  scope :search, lambda { |term|
    pattern = "%#{term.to_s.downcase}%"
    left_joins(:user).where(
      "LOWER(COALESCE(paypal_payments.paypal_id, '')) LIKE :q " \
      "OR LOWER(COALESCE(paypal_payments.payer_name, '')) LIKE :q " \
      "OR LOWER(COALESCE(paypal_payments.payer_email, '')) LIKE :q " \
      "OR LOWER(COALESCE(paypal_payments.status, '')) LIKE :q " \
      "OR LOWER(COALESCE(users.full_name, '')) LIKE :q " \
      "OR LOWER(COALESCE(users.email, '')) LIKE :q",
      q: pattern
    )
  }

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

  def user_id_changed_to_present?
    saved_change_to_user_id? && user_id.present?
  end

  def notify_user_of_link
    user.on_paypal_payment_linked(self)
  end
end
