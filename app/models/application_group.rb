class ApplicationGroup < ApplicationRecord
  belongs_to :application
  has_and_belongs_to_many :users

  validates :name, presence: true
  validates :authentik_name, presence: true
end
