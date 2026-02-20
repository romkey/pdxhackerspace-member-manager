class SeedNewEmailTemplates < ActiveRecord::Migration[8.1]
  def up
    EmailTemplate.seed_defaults!
  end

  def down
    # Don't delete templates on rollback; they may have been customized
  end
end
