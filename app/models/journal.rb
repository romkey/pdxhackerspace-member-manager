class Journal < ApplicationRecord
  belongs_to :user
  belongs_to :actor_user, class_name: "User", optional: true

  validates :action, presence: true
  validates :changes_json, presence: true
  validates :changed_at, presence: true
end

