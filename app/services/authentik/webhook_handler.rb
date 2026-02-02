# SPDX-FileCopyrightText: 2026 John Romkey
#
# SPDX-License-Identifier: CC0-1.0

module Authentik
  class WebhookHandler
    def call(payload)
      event_type = extract_event_type(payload)
      model_type = extract_model_type(payload)

      Rails.logger.info("[Authentik Webhook] Processing event type: #{event_type}, model: #{model_type}")

      # Check if this event is for a group we care about
      unless should_process_event?(payload)
        Rails.logger.info("[Authentik Webhook] Skipping event - not for a synced group")
        return { status: 'filtered', reason: 'not_synced_group' }
      end

      case model_type
      when 'user'
        handle_user_event(event_type, payload)
      when 'group'
        handle_group_event(event_type, payload)
      else
        # Fall back to original behavior for unknown models
        handle_user_event(event_type, payload)
      end
    end

    private

    def extract_event_type(payload)
      # Try different payload structures
      payload['event_type'] ||
        payload.dig('event', 'action') ||
        payload['action'] ||
        'unknown'
    end

    def extract_model_type(payload)
      # Try to determine what model this event is for
      model_app = payload.dig('context', 'model_app') ||
                  payload.dig('event', 'context', 'model_app') ||
                  payload['model_app']

      model_name = payload.dig('context', 'model_name') ||
                   payload.dig('event', 'context', 'model_name') ||
                   payload['model_name']

      return 'group' if model_name&.downcase == 'group' || model_app&.include?('group')
      return 'user' if model_name&.downcase == 'user' || model_app&.include?('user')

      # Check if payload contains user-like or group-like data
      model_data = payload.dig('context', 'model') || {}
      return 'user' if model_data['username'].present? || model_data['email'].present?
      return 'group' if model_data['users'].present? || (model_data['name'].present? && model_data['users_obj'].present?)

      'unknown'
    end

    def should_process_event?(payload)
      # Get synced group IDs from ApplicationGroups in the database
      synced_group_ids = ApplicationGroup.synced_authentik_group_ids

      # If no synced groups configured, process all events (backward compatible)
      return true if synced_group_ids.blank?

      # Also always allow if the main group_id is in the event
      main_group_id = AuthentikConfig.settings.group_id
      synced_group_ids = synced_group_ids + [main_group_id] if main_group_id.present?

      # Extract group IDs from the event
      event_group_ids = extract_group_ids_from_event(payload)

      # If we can't determine groups, process anyway (to be safe)
      return true if event_group_ids.empty?

      # Check if any of the event's groups are in our synced list
      (event_group_ids & synced_group_ids).any?
    end

    def extract_group_ids_from_event(payload)
      group_ids = []

      # For group events, the group ID is the model PK
      model_data = payload.dig('context', 'model') || {}
      if model_data['users'].present? || model_data['users_obj'].present?
        group_ids << model_data['pk'].to_s if model_data['pk'].present?
      end

      # For user events, check the user's groups
      if model_data['groups'].present?
        model_data['groups'].each do |group|
          group_ids << (group.is_a?(Hash) ? group['pk'].to_s : group.to_s)
        end
      end

      # Check for group in other payload locations
      payload_group = payload.dig('context', 'group') || payload['group']
      group_ids << payload_group['pk'].to_s if payload_group.is_a?(Hash) && payload_group['pk'].present?
      group_ids << payload_group.to_s if payload_group.is_a?(String) && payload_group.present?

      group_ids.compact.uniq
    end

    def handle_user_event(event_type, payload)
      case event_type
      when 'model_updated', 'model_created', 'user_write'
        handle_user_change(payload)
      when 'model_deleted'
        handle_user_deletion(payload)
      else
        Rails.logger.info("[Authentik Webhook] Ignoring user event type: #{event_type}")
        { status: 'ignored', event_type: event_type }
      end
    end

    def handle_group_event(event_type, payload)
      case event_type
      when 'model_updated'
        handle_group_membership_change(payload)
      when 'model_deleted'
        handle_group_deletion(payload)
      else
        Rails.logger.info("[Authentik Webhook] Ignoring group event type: #{event_type}")
        { status: 'ignored', event_type: event_type, model: 'group' }
      end
    end

    def handle_group_membership_change(payload)
      group_data = payload.dig('context', 'model') || {}
      group_id = group_data['pk']&.to_s
      group_name = group_data['name']

      if group_id.blank?
        Rails.logger.warn("[Authentik Webhook] No group ID found in membership change payload")
        return { status: 'skipped', reason: 'no_group_id' }
      end

      Rails.logger.info("[Authentik Webhook] Group membership change detected for group: #{group_name} (#{group_id})")

      # Trigger a sync for this group to update user memberships
      # This will be handled by the existing sync infrastructure
      Authentik::GroupSyncJob.perform_later

      { status: 'sync_queued', group_id: group_id, group_name: group_name }
    end

    def handle_group_deletion(payload)
      group_data = payload.dig('context', 'model') || {}
      group_id = group_data['pk']&.to_s
      group_name = group_data['name']

      if group_id.blank?
        Rails.logger.warn("[Authentik Webhook] No group ID found in deletion payload")
        return { status: 'skipped', reason: 'no_group_id' }
      end

      Rails.logger.warn("[Authentik Webhook] Group deleted: #{group_name} (#{group_id})")

      # Log this as a significant event - group deletion may affect members
      # You may want to notify admins or take other action here

      { status: 'group_deleted', group_id: group_id, group_name: group_name }
    end

    def handle_user_change(payload)
      user_data = extract_user_data(payload)

      if user_data.blank? || user_data['pk'].blank?
        Rails.logger.warn("[Authentik Webhook] No user data found in payload")
        return { status: 'skipped', reason: 'no_user_data' }
      end

      authentik_id = user_data['pk'].to_s

      authentik_user = AuthentikUser.find_or_initialize_by(authentik_id: authentik_id)
      was_new = authentik_user.new_record?

      authentik_user.assign_attributes(
        username: user_data['username'],
        email: user_data['email'],
        full_name: user_data['name'] || user_data['full_name'],
        is_active: user_data['is_active'] != false,
        is_superuser: user_data['is_superuser'] == true,
        raw_attributes: merge_raw_attributes(authentik_user.raw_attributes, user_data, payload),
        last_synced_at: Time.current
      )

      # Auto-link by authentik_id if not already linked
      if authentik_user.user_id.nil?
        user = User.find_by(authentik_id: authentik_id)
        authentik_user.user = user if user
      end

      authentik_user.save!

      # Sync changes to the linked User record (if any)
      user_sync_result = sync_to_linked_user(authentik_user, user_data)

      # Create journal entry if there are discrepancies with linked user
      if authentik_user.has_discrepancies? && authentik_user.user
        create_discrepancy_journal_entry(authentik_user)
      end

      # Update MemberSource statistics
      MemberSource.for('authentik').refresh_statistics!

      Rails.logger.info("[Authentik Webhook] #{was_new ? 'Created' : 'Updated'} AuthentikUser: #{authentik_id}")
      { status: was_new ? 'created' : 'updated', authentik_id: authentik_id, user_sync: user_sync_result }
    end

    def handle_user_deletion(payload)
      user_data = extract_user_data(payload)
      authentik_id = user_data['pk']&.to_s || extract_authentik_id_from_context(payload)

      if authentik_id.blank?
        Rails.logger.warn("[Authentik Webhook] No authentik_id found for deletion")
        return { status: 'skipped', reason: 'no_authentik_id' }
      end

      authentik_user = AuthentikUser.find_by(authentik_id: authentik_id)

      if authentik_user
        authentik_user.update!(
          is_active: false,
          last_synced_at: Time.current,
          raw_attributes: merge_raw_attributes(authentik_user.raw_attributes, { 'deleted_at' => Time.current.iso8601 }, payload)
        )

        # Update MemberSource statistics
        MemberSource.for('authentik').refresh_statistics!

        Rails.logger.info("[Authentik Webhook] Marked AuthentikUser as inactive: #{authentik_id}")
        { status: 'deactivated', authentik_id: authentik_id }
      else
        Rails.logger.info("[Authentik Webhook] AuthentikUser not found for deletion: #{authentik_id}")
        { status: 'not_found', authentik_id: authentik_id }
      end
    end

    def extract_user_data(payload)
      # Handle different payload structures from Authentik
      # Custom webhook body mapping format
      payload['user_data'] ||
        # Default model context
        payload.dig('context', 'model') ||
        # Event context
        payload.dig('context') ||
        # Direct user data
        payload['user'] ||
        {}
    end

    def extract_authentik_id_from_context(payload)
      payload.dig('context', 'model', 'pk')&.to_s ||
        payload.dig('context', 'pk')&.to_s ||
        payload.dig('user_data', 'pk')&.to_s
    end

    def merge_raw_attributes(existing, user_data, full_payload = nil)
      merged = existing.dup
      merged['webhook'] = user_data
      merged['webhook_received_at'] = Time.current.iso8601
      merged['full_payload'] = full_payload if full_payload.present?
      merged
    end

    def sync_to_linked_user(authentik_user, user_data)
      user = authentik_user.user
      return { status: 'skipped', reason: 'no_linked_user' } unless user

      # Prevent sync loop - don't sync back to Authentik when we update the User
      Current.skip_authentik_sync = true

      sync = Authentik::UserSync.new(user)
      result = sync.apply_authentik_data(user_data)

      Rails.logger.info("[Authentik Webhook] Synced to User #{user.id}: #{result[:status]}")
      result
    rescue StandardError => e
      Rails.logger.error("[Authentik Webhook] Failed to sync to User: #{e.message}")
      { status: 'error', error: e.message }
    ensure
      Current.skip_authentik_sync = false
    end

    def create_discrepancy_journal_entry(authentik_user)
      discrepancy_fields = authentik_user.discrepancies.map { |d| d[:field] }.join(', ')

      Journal.create!(
        user: authentik_user.user,
        action: 'authentik_discrepancy',
        changes_json: {
          'authentik_discrepancy' => {
            'fields' => discrepancy_fields,
            'authentik_user_id' => authentik_user.id,
            'discrepancies' => authentik_user.discrepancies
          }
        },
        changed_at: Time.current,
        highlight: true
      )
    end
  end
end
