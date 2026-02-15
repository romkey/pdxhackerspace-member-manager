class CreateAccessControllerTypeTrainingTopics < ActiveRecord::Migration[8.1]
  def change
    create_table :access_controller_type_training_topics do |t|
      t.references :access_controller_type, null: false, foreign_key: true,
                   index: { name: 'idx_act_training_topics_on_act_id' }
      t.references :training_topic, null: false, foreign_key: true,
                   index: { name: 'idx_act_training_topics_on_topic_id' }
      t.timestamps
    end

    add_index :access_controller_type_training_topics,
              %i[access_controller_type_id training_topic_id],
              unique: true,
              name: 'idx_act_training_topics_unique'
  end
end
