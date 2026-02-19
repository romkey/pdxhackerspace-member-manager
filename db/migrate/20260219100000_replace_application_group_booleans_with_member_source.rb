class ReplaceApplicationGroupBooleansWithMemberSource < ActiveRecord::Migration[8.0]
  def up
    add_column :application_groups, :member_source, :string, default: 'manual', null: false
    add_reference :application_groups, :sync_with_group, foreign_key: { to_table: :application_groups }, null: true
    add_column :application_groups, :authentik_policy_id, :string

    add_index :application_groups, :member_source
    add_index :application_groups, :authentik_policy_id

    execute <<~SQL
      UPDATE application_groups SET member_source = 'active_members' WHERE use_default_members_group = true;
      UPDATE application_groups SET member_source = 'admin_members' WHERE use_default_admins_group = true;
      UPDATE application_groups SET member_source = 'can_train' WHERE use_can_train = true;
      UPDATE application_groups SET member_source = 'trained_in' WHERE use_trained_in = true;
    SQL

    remove_column :application_groups, :use_default_members_group
    remove_column :application_groups, :use_default_admins_group
    remove_column :application_groups, :use_can_train
    remove_column :application_groups, :use_trained_in
  end

  def down
    add_column :application_groups, :use_default_members_group, :boolean, default: false, null: false
    add_column :application_groups, :use_default_admins_group, :boolean, default: false, null: false
    add_column :application_groups, :use_can_train, :boolean, default: false, null: false
    add_column :application_groups, :use_trained_in, :boolean, default: false, null: false

    execute <<~SQL
      UPDATE application_groups SET use_default_members_group = true WHERE member_source = 'active_members';
      UPDATE application_groups SET use_default_admins_group = true WHERE member_source = 'admin_members';
      UPDATE application_groups SET use_can_train = true WHERE member_source = 'can_train';
      UPDATE application_groups SET use_trained_in = true WHERE member_source = 'trained_in';
    SQL

    remove_index :application_groups, :authentik_policy_id
    remove_index :application_groups, :member_source
    remove_column :application_groups, :authentik_policy_id
    remove_reference :application_groups, :sync_with_group
    remove_column :application_groups, :member_source
  end
end
