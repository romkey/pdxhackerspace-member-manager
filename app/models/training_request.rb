class TrainingRequest < ApplicationRecord
  STATUSES = %w[pending responded].freeze

  belongs_to :user
  belongs_to :training_topic
  belongs_to :responded_by, class_name: 'User', optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :share_contact_info, inclusion: { in: [true, false] }
  validates :training_topic_id, uniqueness: {
    scope: :user_id,
    conditions: -> { where(status: 'pending') },
    message: 'already has an active request for this member'
  }

  scope :pending, -> { where(status: 'pending') }
  scope :responded, -> { where(status: 'responded') }
  scope :newest_first, -> { order(created_at: :desc) }

  def pending?
    status == 'pending'
  end

  def responded?
    status == 'responded'
  end

  def respond!(responder)
    update!(status: 'responded', responded_by: responder, responded_at: Time.current)
  end
end
