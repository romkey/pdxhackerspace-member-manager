class CreateTrainings < ActiveRecord::Migration[7.1]
  def change
    create_table :trainings do |t|
      t.references :trainee, null: false, foreign_key: { to_table: :users }
      t.references :trainer, null: false, foreign_key: { to_table: :users }
      t.references :training_topic, null: false, foreign_key: true
      t.datetime :trained_at, null: false
      t.text :notes

      t.timestamps
    end
    
    add_index :trainings, :trained_at
  end
end
