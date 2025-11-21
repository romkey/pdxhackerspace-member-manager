class AddTrainingTopicFlagsToApplicationGroups < ActiveRecord::Migration[7.1]
  def change
    add_column :application_groups, :use_can_train, :boolean, default: false, null: false
    add_column :application_groups, :use_trained_in, :boolean, default: false, null: false
    add_reference :application_groups, :training_topic, null: true, foreign_key: true
  end
end
