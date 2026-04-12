class AddEmailRewritingAiProfile < ActiveRecord::Migration[8.1]
  def up
    AiOllamaProfile.reset_column_information
    AiOllamaProfile.seed_defaults!
  end

  def down
    AiOllamaProfile.where(key: 'email_rewriting').delete_all
  end
end
