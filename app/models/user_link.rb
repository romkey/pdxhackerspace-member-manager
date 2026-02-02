class UserLink < ApplicationRecord
  belongs_to :user

  validates :title, presence: true
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: 'must be a valid URL' }

  scope :ordered, -> { order(:position, :created_at) }

  # Common link type icons based on URL patterns
  def icon_class
    case url.downcase
    when /github\.com/
      'bi-github'
    when /linkedin\.com/
      'bi-linkedin'
    when /twitter\.com|x\.com/
      'bi-twitter-x'
    when /instagram\.com/
      'bi-instagram'
    when /facebook\.com/
      'bi-facebook'
    when /youtube\.com/
      'bi-youtube'
    when /mastodon|hachyderm|fosstodon/
      'bi-mastodon'
    when /gitlab\.com/
      'bi-gitlab'
    when /reddit\.com/
      'bi-reddit'
    when /discord\.com|discord\.gg/
      'bi-discord'
    when /twitch\.tv/
      'bi-twitch'
    else
      'bi-link-45deg'
    end
  end
end
