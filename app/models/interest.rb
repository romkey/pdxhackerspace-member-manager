class Interest < ApplicationRecord
  has_many :user_interests, dependent: :destroy
  has_many :users, through: :user_interests

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  before_save :normalize_name

  scope :alphabetical,   -> { order(:name) }
  scope :by_popularity,  lambda {
    left_joins(:user_interests).group(:id).order(Arel.sql('COUNT(user_interests.id) DESC, interests.name ASC'))
  }
  scope :seeded_set,     -> { where(seeded: true) }
  scope :needs_review,   -> { where(needs_review: true) }
  scope :approved,       -> { where(needs_review: false) }

  # Whether any seeded interests have been installed yet.
  def self.seeded?
    seeded_set.exists?
  end

  # Returns up to `limit` interests to suggest: most popular first, then random filler.
  # All interests (including member-suggested ones pending review) are surfaced immediately.
  def self.suggested(limit: 20, exclude_ids: [])
    top = by_popularity.where.not(id: exclude_ids).limit(limit).to_a
    return top if top.size >= limit

    filler_ids = top.map(&:id) + exclude_ids
    filler = where.not(id: filler_ids).order(Arel.sql('RANDOM()')).limit(limit - top.size).to_a
    top + filler
  end

  def member_count
    user_interests.count
  end

  private

  def normalize_name
    self.name = name.strip if name.present?
  end
end
