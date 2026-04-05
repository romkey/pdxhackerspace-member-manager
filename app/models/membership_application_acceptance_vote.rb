# frozen_string_literal: true

class MembershipApplicationAcceptanceVote < ApplicationRecord
  DECISIONS = %w[accept reject].freeze

  belongs_to :membership_application
  belongs_to :user

  validates :decision, presence: true, inclusion: { in: DECISIONS }
  validates :user_id, uniqueness: { scope: :membership_application_id }
end
