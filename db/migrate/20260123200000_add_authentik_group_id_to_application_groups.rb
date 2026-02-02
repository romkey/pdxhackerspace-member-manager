class AddAuthentikGroupIdToApplicationGroups < ActiveRecord::Migration[7.1]
  def change
    add_column :application_groups, :authentik_group_id, :string
    add_index :application_groups, :authentik_group_id
  end
end
