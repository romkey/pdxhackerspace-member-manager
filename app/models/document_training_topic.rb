class DocumentTrainingTopic < ApplicationRecord
  belongs_to :document
  belongs_to :training_topic
end
