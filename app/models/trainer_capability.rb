class TrainerCapability < ApplicationRecord
  belongs_to :user
  belongs_to :training_topic

  validates :user_id, uniqueness: { scope: :training_topic_id }
end
