class AddSponsoredToMembershipStatus < ActiveRecord::Migration[7.1]
  # No database changes needed - membership_status is a string column
  # and "sponsored" is added to the enum in the User model
  def change
  end
end
