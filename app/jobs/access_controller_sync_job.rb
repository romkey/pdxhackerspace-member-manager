require 'open3'
require 'json'

class AccessControllerSyncJob < ApplicationJob
  queue_as :default

  def perform(access_controller_id, user_id = nil)
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

    payload = AccessControllerPayloadBuilder.call(access_controller_type: type)
    env = build_env(access_controller, user_id)

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

  def build_env(access_controller, user_id)
    env = {}

    # Custom environment variables from the access controller (lowest priority, can be overridden)
    env.merge!(access_controller.parsed_environment_variables)

    env['ACCESS_TOKEN'] = access_controller.access_token if access_controller.access_token.present?
    env['ACCESS_CONTROLLER_NICKNAME'] = access_controller.nickname if access_controller.nickname.present?

    # Pass through syslog configuration
    env['SYSLOG_SERVER'] = ENV['SYSLOG_SERVER'] if ENV['SYSLOG_SERVER'].present?
    env['SYSLOG_PORT'] = ENV['SYSLOG_PORT'] if ENV['SYSLOG_PORT'].present?

    if user_id.present?
      user = User.find_by(id: user_id)
      if user
        env['MM_USER_ID'] = user.id.to_s
        env['MM_USER_NAME'] = user.full_name.presence || user.display_name
        env['MM_USER_EMAIL'] = user.email if user.email.present?
        env['MM_USER_USERNAME'] = user.username if user.username.present?
      end
    end

    env
  end
end
