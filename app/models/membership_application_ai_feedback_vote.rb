# frozen_string_literal: true

class MembershipApplicationAiFeedbackVote < ApplicationRecord
  STANCES = %w[agree disagree].freeze

  belongs_to :membership_application
  belongs_to :user

  validates :stance, presence: true, inclusion: { in: STANCES }
  validates :user_id, uniqueness: { scope: :membership_application_id }
end
