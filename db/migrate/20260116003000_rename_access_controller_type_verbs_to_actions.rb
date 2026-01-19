class RenameAccessControllerTypeVerbsToActions < ActiveRecord::Migration[7.1]
  def change
    rename_column :access_controller_types, :verbs, :actions
  end
end
