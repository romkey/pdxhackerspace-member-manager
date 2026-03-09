class MembershipPlan < ApplicationRecord
  PLAN_TYPES = %w[primary supplementary].freeze

  belongs_to :user, optional: true

  has_many :users, dependent: :nullify # Users with this as their primary plan
  has_many :user_supplementary_plans, dependent: :destroy
  has_many :supplementary_users, through: :user_supplementary_plans, source: :user
  has_many :cash_payments, dependent: :destroy

  validates :name, presence: true
  validates :name, uniqueness: true, if: -> { user_id.nil? }
  validates :cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :billing_frequency, presence: true, inclusion: { in: %w[monthly yearly one-time] }
  validates :plan_type, presence: true, inclusion: { in: PLAN_TYPES }
  validates :display_order, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :payment_link,
            format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]),
                      message: 'must be a valid URL' },
            allow_blank: true

  before_validation :enforce_personal_plan_defaults, if: :personal?

  scope :ordered, -> { order(:display_order, :name) }
  scope :shared, -> { where(user_id: nil) }
  scope :personal, -> { where.not(user_id: nil) }
  scope :primary, -> { where(plan_type: 'primary') }
  scope :supplementary, -> { where(plan_type: 'supplementary') }
  scope :with_payment_link, -> { where.not(payment_link: [nil, '']) }
  scope :with_transaction_subject, -> { where.not(paypal_transaction_subject: [nil, '']) }
  scope :visible, -> { where(visible: true) }
  scope :manual, -> { where(manual: true) }

  def display_name
    if personal?
      "#{name} (#{user&.display_name}) - $#{format('%.2f', cost)}/#{billing_frequency}"
    else
      "#{name} - $#{format('%.2f', cost)}/#{billing_frequency}"
    end
  end

  def has_payment_link?
    payment_link.present?
  end

  def personal?
    user_id.present?
  end

  def primary?
    plan_type == 'primary'
  end

  def supplementary?
    plan_type == 'supplementary'
  end

  def billing_cycle_duration
    case billing_frequency
    when 'monthly'  then 1.month
    when 'yearly'   then 1.year
    when 'one-time' then nil
    end
  end

  def self.find_by_transaction_subject(raw_json_string)
    with_transaction_subject.find do |plan|
      raw_json_string.include?(plan.paypal_transaction_subject)
    end
  end

  private

  def enforce_personal_plan_defaults
    self.manual = true
    self.visible = false
  end
end
