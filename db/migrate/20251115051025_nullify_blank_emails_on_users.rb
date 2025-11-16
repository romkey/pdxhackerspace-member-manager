class NullifyBlankEmailsOnUsers < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      UPDATE users
      SET email = NULL
      WHERE email = ''
    SQL
  end

  def down
    # no-op
  end
end
