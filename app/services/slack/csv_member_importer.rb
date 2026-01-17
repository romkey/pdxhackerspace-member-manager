require 'csv'

module Slack
  class CsvMemberImporter
    ACTIVE_STATUS_VALUES = ['Admin', 'Member'].freeze
    ADMIN_STATUS_VALUES = ['Admin', 'Primary Owner'].freeze
    OWNER_STATUS_VALUES = ['Primary Owner'].freeze
    BOT_STATUS_VALUES = ['Bot'].freeze
    DEACTIVATED_STATUS_VALUES = ['Deactivated'].freeze

    def initialize(logger: Rails.logger)
      @logger = logger
    end

    def call(file)
      raise ArgumentError, 'CSV file is missing' if file.blank?

      csv_content = file.read.force_encoding('UTF-8')
      csv_data = CSV.parse(csv_content, headers: true)

      counts = { imported: 0, updated: 0, skipped: 0 }

      SlackUser.transaction do
        csv_data.each do |row|
          attrs = normalize_row(row)
          slack_id = attrs[:slack_id]

          if slack_id.blank?
            counts[:skipped] += 1
            next
          end

          record = SlackUser.find_or_initialize_by(slack_id: slack_id)
          record.assign_attributes(attrs.except(:raw_attributes))
          record.raw_attributes = merge_raw_attributes(record.raw_attributes, attrs[:raw_attributes])

          if record.new_record?
            counts[:imported] += 1
          else
            counts[:updated] += 1
          end

          record.save!
        rescue StandardError => e
          counts[:skipped] += 1
          @logger.error("Failed to import Slack CSV user #{slack_id.presence || 'unknown'}: #{e.message}")
        end
      end

      counts
    end

    private

    def normalize_row(row)
      row_hash = row.to_h.transform_keys { |key| key.to_s.strip.downcase }
      status = row_hash['status'].to_s.strip

      {
        slack_id: row_hash['userid'].to_s.strip.presence,
        username: row_hash['username'].to_s.strip.presence,
        email: row_hash['email'].to_s.strip.presence,
        real_name: row_hash['fullname'].to_s.strip.presence,
        display_name: row_hash['displayname'].to_s.strip.presence,
        slack_status: ACTIVE_STATUS_VALUES.include?(status),
        is_admin: ADMIN_STATUS_VALUES.include?(status),
        is_owner: OWNER_STATUS_VALUES.include?(status),
        is_bot: BOT_STATUS_VALUES.include?(status),
        deleted: DEACTIVATED_STATUS_VALUES.include?(status),
        last_synced_at: Time.current,
        raw_attributes: {
          'csv' => row_hash,
          'csv_imported_at' => Time.current.iso8601
        }
      }
    end

    def merge_raw_attributes(existing, incoming)
      base = existing.is_a?(Hash) ? existing.deep_dup : {}
      base.merge(incoming)
    end
  end
end
