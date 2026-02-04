class RechargePayment < ApplicationRecord
  belongs_to :user, optional: true

  validates :recharge_id, presence: true, uniqueness: true

  scope :ordered, -> { order(processed_at: :desc, created_at: :desc) }
  scope :for_user, ->(user) { where(user_id: user.id) }
  
  # Unmatched payments - no user with matching recharge_customer_id
  scope :unmatched, -> {
    where.not(customer_id: [nil, ''])
         .where.not(customer_id: User.where.not(recharge_customer_id: [nil, '']).select(:recharge_customer_id))
  }

  before_validation :normalize_email
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

  def normalize_email
    self.customer_email = customer_email.to_s.strip.downcase.presence
  end
  
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
