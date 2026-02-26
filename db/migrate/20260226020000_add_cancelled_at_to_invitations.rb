class AddCancelledAtToInvitations < ActiveRecord::Migration[8.1]
  def change
    add_column :invitations, :cancelled_at, :datetime
  end
end
