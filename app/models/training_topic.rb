class TrainingTopic < ApplicationRecord
  has_many :trainer_capabilities, dependent: :destroy
  has_many :trainers, through: :trainer_capabilities, source: :user
  has_many :trainings, dependent: :destroy
  has_many :training_requests, dependent: :destroy
  has_many :links, class_name: 'TrainingTopicLink', dependent: :destroy
  has_many :document_training_topics, dependent: :destroy
  has_many :documents, through: :document_training_topics
  has_many :application_groups, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :offered_to_members, inclusion: { in: [true, false] }

  scope :offered_for_members, -> { where(offered_to_members: true) }
  scope :with_trainers, -> { joins(:trainer_capabilities).distinct }
  scope :available_for_member_requests, -> { offered_for_members.with_trainers.order(:name) }

  after_create_commit :provision_authentik_groups

  private

  def provision_authentik_groups
    defaults = DefaultSetting.instance
    app = Application.find_or_create_by!(name: Authentik::CoreGroupProvisioner::SYSTEM_APP_NAME)
    slug = name.parameterize

    app.application_groups.find_or_create_by!(member_source: 'trained_in', training_topic: self) do |g|
      g.name = "Trained: #{name}"
      g.authentik_name = "#{defaults.trained_on_prefix}:#{slug}"
    end

    app.application_groups.find_or_create_by!(member_source: 'can_train', training_topic: self) do |g|
      g.name = "Can Train: #{name}"
      g.authentik_name = "#{defaults.can_train_prefix}:#{slug}"
    end
  rescue StandardError => e
    Rails.logger.error("[TrainingTopic] Failed to provision Authentik groups for '#{name}': #{e.message}")
  end
end
