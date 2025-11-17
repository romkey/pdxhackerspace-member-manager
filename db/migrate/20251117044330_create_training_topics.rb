class CreateTrainingTopics < ActiveRecord::Migration[7.1]
  def change
    create_table :training_topics do |t|
      t.string :name, null: false
      t.text :description

      t.timestamps
    end
    
    add_index :training_topics, :name, unique: true
  end
end
