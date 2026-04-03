class CreateAiOllamaProfiles < ActiveRecord::Migration[8.1]
  def up
    create_table :ai_ollama_profiles do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :base_url
      t.string :model
      t.text :prompt
      t.boolean :enabled, default: true, null: false
      t.string :health_status, default: 'unknown', null: false
      t.datetime :last_health_check_at
      t.text :last_health_error
      t.integer :display_order, default: 0, null: false
      t.timestamps
    end
    add_index :ai_ollama_profiles, :key, unique: true

    say_with_time 'Seeding AI Ollama profiles' do
      AiOllamaProfile.reset_column_information
      AiOllamaProfile.seed_defaults!
    end
  end

  def down
    drop_table :ai_ollama_profiles
  end
end
