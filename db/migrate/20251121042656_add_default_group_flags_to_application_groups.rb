class AddDefaultGroupFlagsToApplicationGroups < ActiveRecord::Migration[7.1]
  def change
    add_column :application_groups, :use_default_members_group, :boolean, default: false, null: false
    add_column :application_groups, :use_default_admins_group, :boolean, default: false, null: false
  end
end
