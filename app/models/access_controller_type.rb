class AccessControllerType < ApplicationRecord
  has_many :access_controllers, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :script_path, presence: true
  validates :enabled, inclusion: { in: [true, false] }

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:name) }
end
