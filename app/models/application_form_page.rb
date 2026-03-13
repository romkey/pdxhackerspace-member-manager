class ApplicationFormPage < ApplicationRecord
  has_many :questions, class_name: 'ApplicationFormQuestion', dependent: :destroy

  validates :title, presence: true

  scope :ordered, -> { order(:position, :id) }

  def to_s
    title
  end
end
