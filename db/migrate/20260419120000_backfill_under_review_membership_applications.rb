# frozen_string_literal: true

class BackfillUnderReviewMembershipApplications < ActiveRecord::Migration[8.1]
  def up
    cutoff = Time.zone.local(2026, 4, 1).beginning_of_day
    MembershipApplication.where(status: 'submitted')
                         .where('COALESCE(submitted_at, created_at) < ?', cutoff)
                         .update_all(status: 'under_review', updated_at: Time.current)
  end

  def down
    cutoff = Time.zone.local(2026, 4, 1).beginning_of_day
    MembershipApplication.where(status: 'under_review')
                         .where('COALESCE(submitted_at, created_at) < ?', cutoff)
                         .update_all(status: 'submitted', updated_at: Time.current)
  end
end
