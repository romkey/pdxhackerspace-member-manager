class AddShowOnAllProfilesToDocuments < ActiveRecord::Migration[7.1]
  def change
    add_column :documents, :show_on_all_profiles, :boolean, default: false, null: false
  end
end
