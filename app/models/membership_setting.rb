class MembershipSetting < ApplicationRecord
  validates :payment_grace_period_days, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :reactivation_grace_period_months, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :invitation_expiry_hours, presence: true, numericality: { greater_than: 0 }
  validates :login_link_expiry_hours, presence: true, numericality: { greater_than: 0 }
  validates :admin_login_link_expiry_minutes, presence: true, numericality: { greater_than: 0 }
  validates :application_verification_expiry_hours, presence: true, numericality: { greater_than: 0 }
  validates :manual_payment_due_soon_days, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Singleton pattern - only one row should exist
  def self.instance
    first_or_create!(
      payment_grace_period_days: 14,
      reactivation_grace_period_months: 3,
      invitation_expiry_hours: 72,
      login_link_expiry_hours: 180,
      admin_login_link_expiry_minutes: 15,
      application_verification_expiry_hours: 24,
      manual_payment_due_soon_days: 7
    )
  end

  # Convenience methods for accessing settings
  def self.payment_grace_period_days
    instance.payment_grace_period_days
  end

  def self.reactivation_grace_period_months
    instance.reactivation_grace_period_months
  end

  def self.invitation_expiry_hours
    instance.invitation_expiry_hours
  end

  def self.login_link_expiry_hours
    instance.login_link_expiry_hours
  end

  def self.admin_login_link_expiry_minutes
    instance.admin_login_link_expiry_minutes
  end

  def self.application_verification_expiry_hours
    instance.application_verification_expiry_hours
  end

  def self.manual_payment_due_soon_days
    instance.manual_payment_due_soon_days
  end

  def self.use_builtin_membership_application?
    instance.use_builtin_membership_application?
  end
end
