class MembershipPlan < ApplicationRecord
  PLAN_TYPES = %w[primary supplementary].freeze

  has_many :users, dependent: :nullify # Users with this as their primary plan
  has_many :user_supplementary_plans, dependent: :destroy
  has_many :supplementary_users, through: :user_supplementary_plans, source: :user

  validates :name, presence: true, uniqueness: true
  validates :cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :billing_frequency, presence: true, inclusion: { in: %w[monthly yearly one-time] }
  validates :plan_type, presence: true, inclusion: { in: PLAN_TYPES }
  validates :payment_link, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: 'must be a valid URL' }, allow_blank: true

  scope :ordered, -> { order(:plan_type, :name) }
  scope :primary, -> { where(plan_type: 'primary') }
  scope :supplementary, -> { where(plan_type: 'supplementary') }
  scope :with_payment_link, -> { where.not(payment_link: [nil, '']) }
  scope :with_transaction_subject, -> { where.not(paypal_transaction_subject: [nil, '']) }

  def display_name
    "#{name} - $#{format('%.2f', cost)}/#{billing_frequency}"
  end

  def has_payment_link?
    payment_link.present?
  end

  def primary?
    plan_type == 'primary'
  end

  def supplementary?
    plan_type == 'supplementary'
  end

  # Find a plan by matching its transaction subject against raw payment JSON
  def self.find_by_transaction_subject(raw_json_string)
    with_transaction_subject.find do |plan|
      raw_json_string.include?(plan.paypal_transaction_subject)
    end
  end
end

