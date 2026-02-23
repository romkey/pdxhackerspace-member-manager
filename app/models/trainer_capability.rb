class TrainerCapability < ApplicationRecord
  belongs_to :user
  belongs_to :training_topic

  validates :user_id, uniqueness: { scope: :training_topic_id }

  after_create_commit :sync_can_train_group
  after_destroy_commit :sync_can_train_group

  private

  def sync_can_train_group
    Authentik::ApplicationGroupMembershipSyncJob.perform_later(%w[can_train])
  end
end
