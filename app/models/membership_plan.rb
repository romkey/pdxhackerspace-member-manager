class MembershipPlan < ApplicationRecord
  has_many :users, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :billing_frequency, presence: true, inclusion: { in: %w[monthly yearly one-time] }
  validates :payment_link, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: 'must be a valid URL' }, allow_blank: true

  scope :ordered, -> { order(:name) }
  scope :with_payment_link, -> { where.not(payment_link: [nil, '']) }

  def display_name
    "#{name} - $#{format('%.2f', cost)}/#{billing_frequency}"
  end

  def has_payment_link?
    payment_link.present?
  end
end

