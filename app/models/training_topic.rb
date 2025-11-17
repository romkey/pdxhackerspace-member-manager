class TrainingTopic < ApplicationRecord
  has_many :trainer_capabilities, dependent: :destroy
  has_many :trainers, through: :trainer_capabilities, source: :user
  has_many :trainings, dependent: :destroy

  validates :name, presence: true, uniqueness: true
end

