# frozen_string_literal: true

class CreateApplicationRejectedEmailTemplate < ActiveRecord::Migration[8.1]
  def up
    return if EmailTemplate.exists?(key: 'application_rejected')

    attrs = EmailTemplate::DEFAULT_TEMPLATES['application_rejected']
    EmailTemplate.create!({ key: 'application_rejected' }.merge(attrs))
  end

  def down
    EmailTemplate.where(key: 'application_rejected').delete_all
  end
end
