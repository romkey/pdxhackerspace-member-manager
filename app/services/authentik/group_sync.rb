module Authentik
  class GroupSync
    attr_reader :client, :application_group

    def initialize(application_group, client: nil)
      @application_group = application_group
      @client = client || Authentik::Client.new
    end

    def create!
      Rails.logger.info("[Authentik::GroupSync] Creating group '#{application_group.authentik_name}'")

      existing = client.find_group_by_name(application_group.authentik_name)
      if existing
        Rails.logger.info("[Authentik::GroupSync] Group already exists with ID #{existing['pk']}")
        application_group.update_column(:authentik_group_id, existing['pk'])
        ensure_expression_policy!
        sync_members!
        return { status: 'exists', group_id: existing['pk'] }
      end

      result = client.create_group(
        name: application_group.authentik_name,
        attributes: build_attributes
      )

      group_id = result['pk']
      Rails.logger.info("[Authentik::GroupSync] Created group with ID #{group_id}")

      application_group.update_column(:authentik_group_id, group_id)
      ensure_expression_policy!
      sync_members!

      { status: 'created', group_id: group_id }
    rescue StandardError => e
      Rails.logger.error("[Authentik::GroupSync] Failed to create group: #{e.message}")
      { status: 'error', error: e.message }
    end

    def update!
      return { status: 'skipped', reason: 'no_authentik_group_id' } if application_group.authentik_group_id.blank?

      Rails.logger.info("[Authentik::GroupSync] Updating group #{application_group.authentik_group_id}")

      client.update_group(
        application_group.authentik_group_id,
        name: application_group.authentik_name,
        attributes: build_attributes
      )

      ensure_expression_policy!

      { status: 'updated', group_id: application_group.authentik_group_id }
    rescue StandardError => e
      Rails.logger.error("[Authentik::GroupSync] Failed to update group: #{e.message}")
      { status: 'error', error: e.message }
    end

    def delete!
      return { status: 'skipped', reason: 'no_authentik_group_id' } if application_group.authentik_group_id.blank?

      Rails.logger.info("[Authentik::GroupSync] Deleting group #{application_group.authentik_group_id}")

      delete_expression_policy!
      client.delete_group(application_group.authentik_group_id)

      { status: 'deleted', group_id: application_group.authentik_group_id }
    rescue StandardError => e
      Rails.logger.error("[Authentik::GroupSync] Failed to delete group: #{e.message}")
      { status: 'error', error: e.message }
    end

    def sync_members!
      return { status: 'skipped', reason: 'no_authentik_group_id' } if application_group.authentik_group_id.blank?

      Rails.logger.info("[Authentik::GroupSync] Syncing members for group #{application_group.authentik_group_id}")

      begin
        authentik_group = client.get_group(application_group.authentik_group_id)
        current_user_pks = (authentik_group['users'] || []).map(&:to_i)
      rescue StandardError => e
        Rails.logger.error("[Authentik::GroupSync] Failed to get group from Authentik: #{e.message}")
        return { status: 'error', error: e.message }
      end

      desired_members = application_group.syncable_members
      desired_user_pks = desired_members.pluck(:authentik_id)
                                        .filter_map do |id|
                                          id.to_i if id.present? && id.to_s.match?(/\A\d+\z/) && id.to_i.positive?
      end

      to_add = desired_user_pks - current_user_pks
      to_remove = current_user_pks - desired_user_pks

      Rails.logger.info("[Authentik::GroupSync] Members to add: #{to_add.count}, to remove: #{to_remove.count}")

      client.set_group_users(application_group.authentik_group_id, desired_user_pks) if to_add.any? || to_remove.any?

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

    def ensure_expression_policy!
      policy_name = application_group.policy_name
      expression = application_group.policy_expression

      if application_group.authentik_policy_id.present?
        begin
          client.update_expression_policy(
            application_group.authentik_policy_id,
            name: policy_name,
            expression: expression
          )
          Rails.logger.info(
            '[Authentik::GroupSync] Renamed/updated expression policy ' \
            "#{application_group.authentik_policy_id} to '#{policy_name}'"
          )
          return { status: 'ok', policy_id: application_group.authentik_policy_id }
        rescue StandardError => e
          Rails.logger.warn(
            '[Authentik::GroupSync] Could not update existing policy ' \
            "#{application_group.authentik_policy_id}: #{e.message}, will find or create"
          )
        end
      end

      existing = client.find_expression_policy_by_name(policy_name)
      if existing
        policy_id = existing['pk']
        client.update_expression_policy(policy_id, expression: expression)
        Rails.logger.info("[Authentik::GroupSync] Updated expression policy #{policy_id}")
      else
        result = client.create_expression_policy(name: policy_name, expression: expression)
        policy_id = result['pk']
        Rails.logger.info("[Authentik::GroupSync] Created expression policy #{policy_id}")
      end

      if application_group.authentik_policy_id != policy_id
        application_group.update_column(:authentik_policy_id,
                                        policy_id)
      end
      { status: 'ok', policy_id: policy_id }
    rescue StandardError => e
      Rails.logger.error("[Authentik::GroupSync] Failed to ensure expression policy: #{e.message}")
      { status: 'error', error: e.message }
    end

    def delete_expression_policy!
      return if application_group.authentik_policy_id.blank?

      client.delete_expression_policy(application_group.authentik_policy_id)
      application_group.update_column(:authentik_policy_id, nil)
      Rails.logger.info("[Authentik::GroupSync] Deleted expression policy #{application_group.authentik_policy_id}")
    rescue StandardError => e
      Rails.logger.error("[Authentik::GroupSync] Failed to delete expression policy: #{e.message}")
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
