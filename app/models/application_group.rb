class ApplicationGroup < ApplicationRecord
  MEMBER_SOURCES = %w[manual active_members admin_members unbanned_members all_members sync_group can_train
                      trained_in].freeze

  POLICY_NAME_PREFIX = 'mm-group-membership'.freeze

  belongs_to :application
  belongs_to :training_topic, optional: true
  belongs_to :sync_with_group, class_name: 'ApplicationGroup', optional: true
  has_and_belongs_to_many :users,
                          after_add: :queue_authentik_membership_sync,
                          after_remove: :queue_authentik_membership_sync

  validates :name, presence: true
  validates :authentik_name, presence: true,
                             format: { with: %r{\A[\w\-.:/ ]+\z},
                                       message: 'may only contain letters, numbers, hyphens, ' \
                                                'underscores, periods, colons, slashes, and spaces' }
  validates :member_source, presence: true, inclusion: { in: MEMBER_SOURCES }
  validates :training_topic_id, presence: true, if: -> { can_train? || trained_in? }
  validates :sync_with_group_id, presence: true, if: -> { sync_group? }

  before_save :clear_authentik_group_id_if_name_changed
  before_save :clear_irrelevant_associations

  scope :with_authentik_group_id, -> { where.not(authentik_group_id: [nil, '']) }
  scope :ordered_by_name, -> { order(:name) }
  scope :with_member_sources, ->(*sources) { where(member_source: sources.flatten) }

  def self.synced_authentik_group_ids
    with_authentik_group_id.pluck(:authentik_group_id).compact.uniq
  end

  MEMBER_SOURCES.each do |source|
    define_method(:"#{source}?") { member_source == source }
  end

  def uses_default_group?
    member_source != 'manual'
  end

  def effective_members
    case member_source
    when 'active_members'
      User.active
    when 'admin_members'
      User.admin
    when 'unbanned_members'
      User.non_service_accounts.where.not(membership_status: 'banned')
    when 'all_members'
      User.non_service_accounts
    when 'sync_group'
      sync_with_group&.effective_members || User.none
    when 'can_train'
      training_topic&.trainers || User.none
    when 'trained_in'
      if training_topic
        User.where(id: User.joins(:trainings_as_trainee)
                       .where(trainings: { training_topic_id: training_topic_id }).select(:id))
      else
        User.none
      end
    else
      users
    end
  end

  def syncable_members
    effective_members.where.not(authentik_id: [nil, ''])
  end

  def unsyncable_members
    effective_members.where(authentik_id: [nil, ''])
  end

  def policy_name
    "#{POLICY_NAME_PREFIX}:#{authentik_name}"
  end

  def policy_expression
    if sync_group? && sync_with_group.present?
      %(return ak_is_group_member(request.user, name="#{sync_with_group.authentik_name}"))
    else
      %(return ak_is_group_member(request.user, name="#{authentik_name}"))
    end
  end

  def policy_only?
    %w[sync_group can_train trained_in].include?(member_source)
  end

  private

  def clear_authentik_group_id_if_name_changed
    return if new_record?
    return unless authentik_name_changed?
    return if authentik_group_id.blank?

    self.authentik_group_id = nil
  end

  def clear_irrelevant_associations
    self.sync_with_group_id = nil unless sync_group?
    return if can_train? || trained_in?

    self.training_topic_id = nil
  end

  def queue_authentik_membership_sync(_user)
    return if Current.skip_authentik_sync
    return if authentik_group_id.blank?

    Authentik::ApplicationGroupMembershipSyncJob.perform_later([member_source])
  end
end
