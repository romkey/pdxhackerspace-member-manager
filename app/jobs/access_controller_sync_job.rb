require 'open3'
require 'json'

class AccessControllerSyncJob < ApplicationJob
  queue_as :default

  def perform(access_controller_id)
    access_controller = AccessController.includes(:access_controller_type).find(access_controller_id)
    return unless access_controller.enabled?

    access_controller.mark_syncing!

    type = access_controller.access_controller_type
    unless type&.enabled?
      access_controller.record_sync_failure!('Access controller type is missing or disabled.')
      return
    end

    script_path = type.script_path.to_s.strip
    if script_path.blank?
      access_controller.record_sync_failure!('Script path is missing.')
      return
    end

    # Build command line arguments
    cmd_args = [script_path]
    if access_controller.script_arguments.present?
      cmd_args += access_controller.script_arguments.split(/\s+/)
    end
    cmd_args << access_controller.hostname

    command_line = cmd_args.map { |a| a.include?(' ') ? "\"#{a}\"" : a }.join(' ')

    # Create log entry
    log = access_controller.access_controller_logs.create!(
      action: 'sync',
      command_line: command_line,
      status: 'running'
    )

    payload = AccessControllerPayloadBuilder.call
    env = build_env(access_controller)

    stdout, stderr, status = Open3.capture3(env, *cmd_args, stdin_data: payload)
    output = [stdout, stderr].map(&:to_s).map(&:strip).reject(&:blank?).join("\n")

    log_status = status.success? ? 'success' : 'failed'
    log.update!(
      output: output.presence,
      exit_code: status.exitstatus,
      status: log_status
    )

    if status.success?
      access_controller.record_sync_success!(output.presence)
    else
      message = output.presence || "Sync failed with exit code #{status.exitstatus}."
      access_controller.record_sync_failure!(message)
    end
  rescue StandardError => e
    error_message = "Sync failed: #{e.class}: #{e.message}"

    if defined?(log) && log.persisted?
      log.update!(output: error_message, status: 'failed')
    end

    access_controller&.record_sync_failure!(error_message)
  end

  private

  def build_env(access_controller)
    env = {}
    if access_controller.access_token.present?
      env['ACCESS_TOKEN'] = access_controller.access_token
    end
    env
  end
end
