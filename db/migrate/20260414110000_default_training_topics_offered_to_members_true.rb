class DefaultTrainingTopicsOfferedToMembersTrue < ActiveRecord::Migration[8.1]
  def up
    change_column_default :training_topics, :offered_to_members, from: false, to: true
    execute 'UPDATE training_topics SET offered_to_members = TRUE'
  end

  def down
    change_column_default :training_topics, :offered_to_members, from: true, to: false
  end
end
