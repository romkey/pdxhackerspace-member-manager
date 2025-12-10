class MembershipPlan < ApplicationRecord
  has_many :users, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :billing_frequency, presence: true, inclusion: { in: %w[monthly yearly one-time] }

  scope :ordered, -> { order(:name) }

  def display_name
    "#{name} - $#{format('%.2f', cost)}/#{billing_frequency}"
  end
end

