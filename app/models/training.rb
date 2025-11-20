class Training < ApplicationRecord
  belongs_to :trainee, class_name: 'User'
  belongs_to :trainer, class_name: 'User', optional: true
  belongs_to :training_topic

  validates :trained_at, presence: true

  scope :recent, -> { order(trained_at: :desc) }
end
