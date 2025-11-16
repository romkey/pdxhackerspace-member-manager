module GoogleSheets
  class SyncJob < ApplicationJob
    queue_as :default

    def perform
      count = GoogleSheets::EntrySynchronizer.new.call
      Rails.logger.info("Synced #{count} Google Sheet entries.")
    rescue StandardError => e
      Rails.logger.error("Google Sheets sync failed: #{e.class} #{e.message}")
      raise
    end
  end
end

