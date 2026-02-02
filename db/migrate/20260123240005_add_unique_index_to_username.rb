class AddUniqueIndexToUsername < ActiveRecord::Migration[7.1]
  def change
    # Remove the existing non-unique index if it exists
    remove_index :users, :username, if_exists: true

    # Add a unique index (allows NULL values - only enforces uniqueness on non-null values)
    add_index :users, :username, unique: true, where: 'username IS NOT NULL'
  end
end
