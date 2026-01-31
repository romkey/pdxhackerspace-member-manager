class CreateTrainingTopicLinks < ActiveRecord::Migration[7.1]
  def change
    create_table :training_topic_links do |t|
      t.references :training_topic, null: false, foreign_key: true
      t.string :title, null: false
      t.string :url, null: false

      t.timestamps
    end
  end
end
