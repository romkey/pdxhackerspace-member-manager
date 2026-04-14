class CreateTrainingRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :training_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.references :training_topic, null: false, foreign_key: true
      t.boolean :share_contact_info, null: false, default: false
      t.string :status, null: false, default: 'pending'
      t.datetime :responded_at
      t.references :responded_by, null: true, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :training_requests, :status
    add_index :training_requests, %i[user_id training_topic_id status], name: 'idx_training_requests_user_topic_status'
  end
end
