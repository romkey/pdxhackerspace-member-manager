class AddOfferedToMembersToTrainingTopics < ActiveRecord::Migration[8.1]
  def change
    add_column :training_topics, :offered_to_members, :boolean, null: false, default: false
    add_index :training_topics, :offered_to_members
  end
end
