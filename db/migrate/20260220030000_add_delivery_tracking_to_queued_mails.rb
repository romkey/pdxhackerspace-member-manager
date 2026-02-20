class AddDeliveryTrackingToQueuedMails < ActiveRecord::Migration[8.1]
  def change
    add_column :queued_mails, :last_error, :text
    add_column :queued_mails, :last_error_at, :datetime
    add_column :queued_mails, :send_attempts, :integer, null: false, default: 0
  end
end
