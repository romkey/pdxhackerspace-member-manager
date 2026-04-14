class AddProviderFieldsToAiOllamaProfiles < ActiveRecord::Migration[8.1]
  def change
    add_reference :ai_ollama_profiles, :ai_provider, foreign_key: { on_delete: :nullify }
    add_column :ai_ollama_profiles, :api_key, :string
    add_column :ai_ollama_profiles, :provider_name_override, :string
    add_column :ai_ollama_profiles, :provider_url_override, :string
    add_column :ai_ollama_profiles, :provider_api_key_override, :string
  end
end
