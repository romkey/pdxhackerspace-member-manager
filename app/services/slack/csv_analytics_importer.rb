require 'csv'

module Slack
  class CsvAnalyticsImporter
    DATE_FORMAT = '%b %d, %Y'.freeze

    def initialize(logger: Rails.logger)
      @logger = logger
    end

    def call(file)
      raise ArgumentError, 'CSV file is missing' if file.blank?

      csv_content = file.read.force_encoding('UTF-8')
      csv_data = CSV.parse(csv_content, headers: true)

      counts = { updated: 0, skipped: 0 }

      SlackUser.transaction do
        csv_data.each do |row|
          attrs = normalize_row(row)

          slack_user = find_slack_user(attrs)
          if slack_user.nil?
            counts[:skipped] += 1
            next
          end

          slack_user.update!(
            last_active_at: attrs[:last_active_at],
            raw_attributes: merge_raw_attributes(slack_user.raw_attributes, attrs[:raw_attributes])
          )
          counts[:updated] += 1
        rescue StandardError => e
          counts[:skipped] += 1
          @logger.error("Failed to import Slack analytics row: #{e.message}")
        end
      end

      counts
    end

    private

    def normalize_row(row)
      row_hash = row.to_h.transform_keys { |key| key.to_s.strip.downcase }
      last_active_at = parse_last_active(row_hash['last active (utc)'])

      {
        slack_id: row_hash['user id'].to_s.strip.presence,
        username: row_hash['username'].to_s.strip.presence,
        last_active_at: last_active_at,
        raw_attributes: {
          'analytics_csv' => row_hash,
          'analytics_imported_at' => Time.current.iso8601
        }
      }
    end

    def find_slack_user(attrs)
      if attrs[:slack_id].present?
        SlackUser.find_by(slack_id: attrs[:slack_id])
      elsif attrs[:username].present?
        SlackUser.find_by('LOWER(username) = ?', attrs[:username].downcase)
      end
    end

    def parse_last_active(value)
      return nil if value.blank?

      date = Date.strptime(value.to_s.strip, DATE_FORMAT)
      Time.zone.local(date.year, date.month, date.day)
    rescue ArgumentError
      nil
    end

    def merge_raw_attributes(existing, incoming)
      base = existing.is_a?(Hash) ? existing.deep_dup : {}
      base.merge(incoming)
    end
  end
end
