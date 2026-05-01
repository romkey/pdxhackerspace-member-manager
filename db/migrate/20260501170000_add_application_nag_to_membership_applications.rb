# frozen_string_literal: true

class AddApplicationNagToMembershipApplications < ActiveRecord::Migration[8.1]
  def up
    add_column :membership_applications, :application_nag_sent_at, :datetime
    add_index :membership_applications, :application_nag_sent_at

    return if EmailTemplate.exists?(key: 'staff_application_nag')

    attrs = EmailTemplate::DEFAULT_TEMPLATES['staff_application_nag']
    EmailTemplate.create!({ key: 'staff_application_nag' }.merge(attrs))
  end

  def down
    EmailTemplate.where(key: 'staff_application_nag').delete_all
    remove_index :membership_applications, :application_nag_sent_at
    remove_column :membership_applications, :application_nag_sent_at
  end
end
