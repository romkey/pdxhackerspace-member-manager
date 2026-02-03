class TextFragment < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :title, presence: true

  # Find a fragment by key, or create a placeholder if it doesn't exist
  def self.find_by_key(key)
    find_by(key: key)
  end

  # Get fragment content, returning nil if fragment doesn't exist
  def self.content_for(key)
    find_by(key: key)&.content
  end

  # Ensure a fragment exists with the given key
  def self.ensure_exists!(key:, title:, content: '')
    find_or_create_by!(key: key) do |fragment|
      fragment.title = title
      fragment.content = content
    end
  end

  # Order by title for display
  scope :ordered, -> { order(:title) }
end
