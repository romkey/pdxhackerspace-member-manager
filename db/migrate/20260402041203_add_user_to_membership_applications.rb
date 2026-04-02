class AddUserToMembershipApplications < ActiveRecord::Migration[8.1]
  def change
    add_reference :membership_applications, :user, null: true, foreign_key: true
  end
end
