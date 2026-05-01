class RechargePayment < ApplicationRecord
  include NormalizesEmail

  normalizes_email_field :customer_email

  belongs_to :user, optional: true
  has_many :payment_events, dependent: :nullify

  validates :recharge_id, presence: true, uniqueness: true

  scope :ordered, -> { order(processed_at: :desc, created_at: :desc) }
  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :search, lambda { |term|
    pattern = "%#{term.to_s.downcase}%"
    left_joins(:user).where(
      "LOWER(COALESCE(recharge_payments.recharge_id, '')) LIKE :q " \
      "OR LOWER(COALESCE(recharge_payments.customer_name, '')) LIKE :q " \
      "OR LOWER(COALESCE(recharge_payments.customer_email, '')) LIKE :q " \
      "OR LOWER(COALESCE(recharge_payments.status, '')) LIKE :q " \
      "OR LOWER(COALESCE(users.full_name, '')) LIKE :q " \
      "OR LOWER(COALESCE(users.email, '')) LIKE :q",
      q: pattern
    )
  }

  # Unmatched payments - no user with matching recharge_customer_id
  scope :unmatched, lambda {
    where.not(customer_id: [nil, ''])
         .where.not(customer_id: User.where.not(recharge_customer_id: [nil, '']).select(:recharge_customer_id))
  }

  before_save :extract_customer_id

  # When a RechargePayment is linked to a User, notify the User to sync data
  after_save :notify_user_of_link, if: :user_id_changed_to_present?

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

  def extract_customer_id
    return if raw_attributes.blank?

    self.customer_id = raw_attributes.dig('customer', 'id') || raw_attributes['customer_id']
  end

  def user_id_changed_to_present?
    saved_change_to_user_id? && user_id.present?
  end

  def notify_user_of_link
    user.on_recharge_payment_linked(self)
  end
end
