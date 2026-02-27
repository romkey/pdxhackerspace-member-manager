class UserInterest < ApplicationRecord
  belongs_to :user
  belongs_to :interest

  validates :user_id,     presence: true
  validates :interest_id, presence: true, uniqueness: { scope: :user_id }
end
