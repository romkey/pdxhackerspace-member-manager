class UserSupplementaryPlan < ApplicationRecord
  belongs_to :user
  belongs_to :membership_plan

  validates :membership_plan_id, uniqueness: { scope: :user_id, message: 'already added to this user' }
  validate :plan_must_be_supplementary

  private

  def plan_must_be_supplementary
    return unless membership_plan

    unless membership_plan.supplementary?
      errors.add(:membership_plan, 'must be a supplementary plan')
    end
  end
end
