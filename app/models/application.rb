class Application < ApplicationRecord
  has_many :application_groups, dependent: :destroy
  has_many :users, through: :application_groups

  validates :name, presence: true
end
