class TrainingTopic < ApplicationRecord
  has_many :trainer_capabilities, dependent: :destroy
  has_many :trainers, through: :trainer_capabilities, source: :user
  has_many :trainings, dependent: :destroy
  has_many :links, class_name: 'TrainingTopicLink', dependent: :destroy
  has_many :document_training_topics, dependent: :destroy
  has_many :documents, through: :document_training_topics

  validates :name, presence: true, uniqueness: true
end
