# SPDX-FileCopyrightText: 2026 John Romkey
#
# SPDX-License-Identifier: CC0-1.0

module Authentik
  class WebhookHandler
    def call(payload)
      event_type = extract_event_type(payload)

      Rails.logger.info("[Authentik Webhook] Processing event type: #{event_type}")

      case event_type
      when 'model_updated', 'model_created', 'user_write'
        handle_user_change(payload)
      when 'model_deleted'
        handle_user_deletion(payload)
      else
        Rails.logger.info("[Authentik Webhook] Ignoring event type: #{event_type}")
        { status: 'ignored', event_type: event_type }
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

      # Create journal entry if there are discrepancies with linked user
      if authentik_user.has_discrepancies? && authentik_user.user
        create_discrepancy_journal_entry(authentik_user)
      end

      # Update MemberSource statistics
      MemberSource.for('authentik').refresh_statistics!

      Rails.logger.info("[Authentik Webhook] #{was_new ? 'Created' : 'Updated'} AuthentikUser: #{authentik_id}")
      { status: was_new ? 'created' : 'updated', authentik_id: authentik_id }
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

    def create_discrepancy_journal_entry(authentik_user)
      discrepancy_fields = authentik_user.discrepancies.map { |d| d[:field] }.join(', ')

      JournalEntry.create!(
        user: authentik_user.user,
        action: 'authentik_discrepancy',
        description: "Authentik data differs from MemberManager: #{discrepancy_fields}",
        metadata: {
          authentik_user_id: authentik_user.id,
          discrepancies: authentik_user.discrepancies
        },
        highlight: true
      )
    end
  end
end
