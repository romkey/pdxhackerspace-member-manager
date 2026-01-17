class AccessLog < ApplicationRecord
  belongs_to :user, optional: true

  scope :recent, -> { where.not(logged_at: nil).order(logged_at: :desc) }
end
