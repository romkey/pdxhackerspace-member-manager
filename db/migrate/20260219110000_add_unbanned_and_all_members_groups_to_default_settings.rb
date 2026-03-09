class AddUnbannedAndAllMembersGroupsToDefaultSettings < ActiveRecord::Migration[8.0]
  def change
    add_column :default_settings, :unbanned_members_group, :string
    add_column :default_settings, :all_members_group, :string

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE default_settings
          SET unbanned_members_group = members_prefix || ':unbanned',
              all_members_group = members_prefix || ':all'
        SQL

        change_column_null :default_settings, :unbanned_members_group, false
        change_column_null :default_settings, :all_members_group, false
      end

      dir.down do
        change_column_null :default_settings, :all_members_group, true
        change_column_null :default_settings, :unbanned_members_group, true
      end
    end
  end
end
