class RemoveUnderReviewMembershipApplicationStatus < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE membership_applications
      SET status = 'submitted'
      WHERE status = 'under_review'
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'Cannot safely infer which submitted applications were previously under_review.'
  end
end
