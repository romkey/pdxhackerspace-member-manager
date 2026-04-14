class CreateAiProviders < ActiveRecord::Migration[8.1]
  def up
    create_table :ai_providers do |t|
      t.string :name, null: false
      t.string :url, null: false
      t.string :api_key

      t.timestamps
    end

    add_index :ai_providers, :name, unique: true

    say_with_time 'Seeding AI providers' do
      AiProvider.seed_defaults!
    end
  end

  def down
    drop_table :ai_providers
  end
end
