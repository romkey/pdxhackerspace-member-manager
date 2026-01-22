require 'open3'

class AccessLogsImportJob < ApplicationJob
  queue_as :default

  def perform
    directory = ENV.fetch('ACCESS_LOGS_DIRECTORY', nil)
    if directory.blank?
      Rails.logger.error('[AccessLogsImportJob] ACCESS_LOGS_DIRECTORY is not set.')
      return
    end

    command = [Rails.root.join('bin/rails').to_s, 'access_logs:import']
    stdout, stderr, status = Open3.capture3({ 'ACCESS_LOGS_DIRECTORY' => directory }, *command)

    Rails.logger.info("[AccessLogsImportJob] access_logs:import stdout:\n#{stdout}") if stdout.present?
    Rails.logger.warn("[AccessLogsImportJob] access_logs:import stderr:\n#{stderr}") if stderr.present?

    return if status.success?

    raise "access_logs:import failed with status #{status.exitstatus}"
  end
end
