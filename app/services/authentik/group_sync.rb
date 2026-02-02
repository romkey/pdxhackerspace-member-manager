module Authentik
  class GroupSync
    attr_reader :client, :application_group

    def initialize(application_group, client: nil)
      @application_group = application_group
      @client = client || Authentik::Client.new
    end

    # Create group in Authentik and set authentik_group_id
    def create!
      Rails.logger.info("[Authentik::GroupSync] Creating group '#{application_group.authentik_name}'")

      # Check if group already exists
      existing = client.find_group_by_name(application_group.authentik_name)
      if existing
        Rails.logger.info("[Authentik::GroupSync] Group already exists with ID #{existing['pk']}")
        application_group.update_column(:authentik_group_id, existing['pk'])
        sync_members!
        return { status: 'exists', group_id: existing['pk'] }
      end

      # Create the group
      result = client.create_group(
        name: application_group.authentik_name,
        attributes: build_attributes
      )

      group_id = result['pk']
      Rails.logger.info("[Authentik::GroupSync] Created group with ID #{group_id}")

      # Save the Authentik group ID
      application_group.update_column(:authentik_group_id, group_id)

      # Sync members
      sync_members!

      { status: 'created', group_id: group_id }
    rescue StandardError => e
      Rails.logger.error("[Authentik::GroupSync] Failed to create group: #{e.message}")
      { status: 'error', error: e.message }
    end

    # Update group name in Authentik
    def update!
      return { status: 'skipped', reason: 'no_authentik_group_id' } if application_group.authentik_group_id.blank?

      Rails.logger.info("[Authentik::GroupSync] Updating group #{application_group.authentik_group_id}")

      client.update_group(
        application_group.authentik_group_id,
        name: application_group.authentik_name,
        attributes: build_attributes
      )

      { status: 'updated', group_id: application_group.authentik_group_id }
    rescue StandardError => e
      Rails.logger.error("[Authentik::GroupSync] Failed to update group: #{e.message}")
      { status: 'error', error: e.message }
    end

    # Delete group from Authentik
    def delete!
      return { status: 'skipped', reason: 'no_authentik_group_id' } if application_group.authentik_group_id.blank?

      Rails.logger.info("[Authentik::GroupSync] Deleting group #{application_group.authentik_group_id}")

      client.delete_group(application_group.authentik_group_id)

      { status: 'deleted', group_id: application_group.authentik_group_id }
    rescue StandardError => e
      Rails.logger.error("[Authentik::GroupSync] Failed to delete group: #{e.message}")
      { status: 'error', error: e.message }
    end

    # Sync members to Authentik
    def sync_members!
      return { status: 'skipped', reason: 'no_authentik_group_id' } if application_group.authentik_group_id.blank?

      Rails.logger.info("[Authentik::GroupSync] Syncing members for group #{application_group.authentik_group_id}")

      # Get current members from Authentik
      begin
        authentik_group = client.get_group(application_group.authentik_group_id)
        current_user_pks = (authentik_group['users'] || []).map(&:to_i)
      rescue StandardError => e
        Rails.logger.error("[Authentik::GroupSync] Failed to get group from Authentik: #{e.message}")
        return { status: 'error', error: e.message }
      end

      # Get desired members (only those with Authentik IDs)
      desired_members = application_group.syncable_members
      desired_user_pks = desired_members.pluck(:authentik_id).map(&:to_i)

      # Calculate differences
      to_add = desired_user_pks - current_user_pks
      to_remove = current_user_pks - desired_user_pks

      Rails.logger.info("[Authentik::GroupSync] Members to add: #{to_add.count}, to remove: #{to_remove.count}")

      # Use set_group_users for efficiency (single API call)
      if to_add.any? || to_remove.any?
        client.set_group_users(application_group.authentik_group_id, desired_user_pks)
      end

      # Report unsyncable members
      unsyncable = application_group.unsyncable_members
      if unsyncable.any?
        Rails.logger.warn("[Authentik::GroupSync] #{unsyncable.count} member(s) without Authentik ID cannot be synced")
      end

      {
        status: 'synced',
        group_id: application_group.authentik_group_id,
        added: to_add.count,
        removed: to_remove.count,
        total: desired_user_pks.count,
        unsyncable: unsyncable.count
      }
    rescue StandardError => e
      Rails.logger.error("[Authentik::GroupSync] Failed to sync members: #{e.message}")
      { status: 'error', error: e.message }
    end

    # Full sync: create if needed, update, and sync members
    def sync!
      if application_group.authentik_group_id.blank?
        create!
      else
        update_result = update!
        return update_result if update_result[:status] == 'error'

        sync_result = sync_members!
        {
          status: 'synced',
          group_id: application_group.authentik_group_id,
          update: update_result,
          members: sync_result
        }
      end
    end

    private

    def build_attributes
      {
        'member_manager_application' => application_group.application.name,
        'member_manager_group_id' => application_group.id,
        'member_manager_synced_at' => Time.current.iso8601
      }
    end
  end
end
