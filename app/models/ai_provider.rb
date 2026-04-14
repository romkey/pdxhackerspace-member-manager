class AiProvider < ApplicationRecord
  DEFAULT_PROVIDERS = [
    { name: 'Claude', url: 'https://api.anthropic.com' },
    { name: 'ChatGPT', url: 'https://api.openai.com' },
    { name: 'Gemini', url: 'https://generativelanguage.googleapis.com' },
    { name: 'Perplexity', url: 'https://api.perplexity.ai' },
    { name: 'Copilot', url: 'https://api.githubcopilot.com' },
    { name: 'Openrouter', url: 'https://openrouter.ai/api' }
  ].freeze

  validates :name, presence: true, uniqueness: true
  validates :url, presence: true

  has_many :ai_ollama_profiles, dependent: :nullify

  scope :ordered, -> { order(:name) }

  def self.seed_defaults!
    DEFAULT_PROVIDERS.each do |attrs|
      row = find_or_initialize_by(name: attrs[:name])
      row.url = attrs[:url]
      row.save!
    end
  end
end
