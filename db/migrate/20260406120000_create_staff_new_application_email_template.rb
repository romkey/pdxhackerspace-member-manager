# frozen_string_literal: true

class CreateStaffNewApplicationEmailTemplate < ActiveRecord::Migration[8.1]
  def up
    return if EmailTemplate.exists?(key: 'staff_new_application')

    attrs = EmailTemplate::DEFAULT_TEMPLATES['staff_new_application']
    EmailTemplate.create!({ key: 'staff_new_application' }.merge(attrs))
  end

  def down
    EmailTemplate.where(key: 'staff_new_application').delete_all
  end
end
