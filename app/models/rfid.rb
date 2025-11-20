class Rfid < ApplicationRecord
  belongs_to :user

  validates :rfid, presence: true, uniqueness: { scope: :user_id }
end
