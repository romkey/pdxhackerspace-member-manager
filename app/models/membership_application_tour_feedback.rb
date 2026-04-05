# frozen_string_literal: true

class MembershipApplicationTourFeedback < ApplicationRecord
  belongs_to :membership_application
  belongs_to :user

  validates :user_id, uniqueness: { scope: :membership_application_id }
  validate :at_least_one_note

  private

  def at_least_one_note
    parts = [attitude, impressions, engagement, fit_feeling].map { |s| s.to_s.strip }.compact_blank
    return if parts.any?

    errors.add(:base, 'Add at least one of attitude, impressions, engagement, or fit.')
  end
end
