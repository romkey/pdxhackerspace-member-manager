class MembershipSetting < ApplicationRecord
  validates :payment_grace_period_days, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :reactivation_grace_period_months, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Singleton pattern - only one row should exist
  def self.instance
    first_or_create!(
      payment_grace_period_days: 14,
      reactivation_grace_period_months: 3
    )
  end

  # Convenience methods for accessing settings
  def self.payment_grace_period_days
    instance.payment_grace_period_days
  end

  def self.reactivation_grace_period_months
    instance.reactivation_grace_period_months
  end
end
