class Document < ApplicationRecord
  has_one_attached :file
  has_many :document_training_topics, dependent: :destroy
  has_many :training_topics, through: :document_training_topics

  validates :title, presence: true
  validates :file, presence: true

  scope :ordered, -> { order(:title) }

  def filename
    file.filename.to_s if file.attached?
  end
end
