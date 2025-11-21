class AddTrainingPrefixesToDefaultSettings < ActiveRecord::Migration[7.1]
  def up
    add_column :default_settings, :trained_on_prefix, :string
    add_column :default_settings, :can_train_prefix, :string
    
    # Populate existing records
    DefaultSetting.reset_column_information
    DefaultSetting.find_each do |setting|
      setting.update_columns(
        trained_on_prefix: "#{setting.members_prefix}:trained-on",
        can_train_prefix: "#{setting.members_prefix}:can-train"
      )
    end
    
    change_column_null :default_settings, :trained_on_prefix, false
    change_column_null :default_settings, :can_train_prefix, false
  end
  
  def down
    remove_column :default_settings, :trained_on_prefix
    remove_column :default_settings, :can_train_prefix
  end
end
