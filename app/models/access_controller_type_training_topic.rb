# Join table linking AccessControllerTypes to required TrainingTopics.
# Users must be trained in ALL associated topics to be synced to controllers of this type.
class AccessControllerTypeTrainingTopic < ApplicationRecord
  belongs_to :access_controller_type
  belongs_to :training_topic

  validates :training_topic_id, uniqueness: { scope: :access_controller_type_id }
end
