# frozen_string_literal: true

class AddDirectMailLogAndApplicationFlowToggle < ActiveRecord::Migration[8.1]
  def change
    change_column_null :mail_log_entries, :queued_mail_id, true

    add_column :mail_log_entries, :delivery_to, :string
    add_column :mail_log_entries, :delivery_subject, :string
    add_column :mail_log_entries, :delivery_mailer, :string
    add_column :mail_log_entries, :delivery_action, :string

    add_column :membership_settings, :use_builtin_membership_application, :boolean, null: false, default: true
  end
end
