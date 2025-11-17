class CreateTrainerCapabilities < ActiveRecord::Migration[7.1]
  def change
    create_table :trainer_capabilities do |t|
      t.references :user, null: false, foreign_key: true
      t.references :training_topic, null: false, foreign_key: true

      t.timestamps
    end
    
    add_index :trainer_capabilities, [:user_id, :training_topic_id], unique: true
  end
end
