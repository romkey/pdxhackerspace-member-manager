class Training < ApplicationRecord
  belongs_to :trainee, class_name: 'User'
  belongs_to :trainer, class_name: 'User', optional: true
  belongs_to :training_topic

  validates :trained_at, presence: true

  scope :recent, -> { order(trained_at: :desc) }

  after_create_commit :sync_trained_in_group
  after_destroy_commit :sync_trained_in_group

  private

  def sync_trained_in_group
    Authentik::ApplicationGroupMembershipSyncJob.perform_later(%w[trained_in])
  end
end
