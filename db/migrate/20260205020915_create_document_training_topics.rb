class CreateDocumentTrainingTopics < ActiveRecord::Migration[7.1]
  def change
    create_table :document_training_topics do |t|
      t.references :document, null: false, foreign_key: true
      t.references :training_topic, null: false, foreign_key: true

      t.timestamps
    end
  end
end
