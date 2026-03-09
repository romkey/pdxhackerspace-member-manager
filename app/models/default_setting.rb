class DefaultSetting < ApplicationRecord
  validates :site_prefix, presence: true
  validates :app_prefix, presence: true
  validates :members_prefix, presence: true
  validates :active_members_group, presence: true
  validates :admins_group, presence: true
  validates :unbanned_members_group, presence: true
  validates :all_members_group, presence: true
  validates :trained_on_prefix, presence: true
  validates :can_train_prefix, presence: true
  validates :sync_inactive_members, inclusion: { in: [true, false] }

  # Singleton pattern - only one record should exist
  def self.instance
    first_or_create! do |setting|
      setting.site_prefix = 'ctrlh'
      setting.app_prefix = 'ctrlh:app'
      setting.members_prefix = 'ctrlh:org:members'
      setting.active_members_group = 'ctrlh:org:members:active'
      setting.admins_group = 'ctrlh:org:members:admins'
      setting.unbanned_members_group = 'ctrlh:org:members:unbanned'
      setting.all_members_group = 'ctrlh:org:members:all'
      setting.trained_on_prefix = 'ctrlh:org:members:trained-on'
      setting.can_train_prefix = 'ctrlh:org:members:can-train'
    end
  end

  before_save :update_derived_fields

  private

  def update_derived_fields
    self.app_prefix = "#{site_prefix}:app" if site_prefix_changed? || app_prefix.blank?
    self.members_prefix = "#{site_prefix}:org:members" if site_prefix_changed? || members_prefix.blank?
    self.active_members_group = "#{members_prefix}:active" if members_prefix_changed? || active_members_group.blank?
    self.admins_group = "#{members_prefix}:admins" if members_prefix_changed? || admins_group.blank?
    if members_prefix_changed? || unbanned_members_group.blank?
      self.unbanned_members_group = "#{members_prefix}:unbanned"
    end
    self.all_members_group = "#{members_prefix}:all" if members_prefix_changed? || all_members_group.blank?
    self.trained_on_prefix = "#{members_prefix}:trained-on" if members_prefix_changed? || trained_on_prefix.blank?
    return unless members_prefix_changed? || can_train_prefix.blank?

    self.can_train_prefix = "#{members_prefix}:can-train"
  end
end
