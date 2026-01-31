class TrainingTopicLink < ApplicationRecord
  belongs_to :training_topic

  validates :title, presence: true
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: 'must be a valid URL' }
end
