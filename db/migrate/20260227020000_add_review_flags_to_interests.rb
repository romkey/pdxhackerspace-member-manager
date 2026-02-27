class AddReviewFlagsToInterests < ActiveRecord::Migration[7.1]
  def change
    add_column :interests, :seeded,       :boolean, default: false, null: false
    add_column :interests, :needs_review, :boolean, default: false, null: false

    add_index :interests, :needs_review
    add_index :interests, :seeded
  end
end
