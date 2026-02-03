class CreateTextFragments < ActiveRecord::Migration[7.1]
  def change
    create_table :text_fragments do |t|
      t.string :key
      t.string :title
      t.text :content

      t.timestamps
    end
    add_index :text_fragments, :key, unique: true
  end
end
