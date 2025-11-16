class AccessLog < ApplicationRecord
  belongs_to :user, optional: true

  scope :recent, -> { order(logged_at: :desc) }
end

