require 'open3'

class AccessControllerBackupJob < ApplicationJob
  queue_as :default

  # Runs the backup action on all enabled access controllers sequentially.
  # Only controllers whose type includes a "backup" action are processed.
  def perform
    AccessController.enabled.ordered.includes(:access_controller_type).find_each do |controller|
      type = controller.access_controller_type
      next unless type&.enabled?
      next unless Array(type.actions).map(&:to_s).include?('backup')

      backup_single(controller, type)
    end
  end

  private

  def backup_single(controller, type)
    script_path = type.script_path.to_s.strip
    return if script_path.blank?

    cmd_args = [script_path, 'backup']
    if controller.script_arguments.present?
      cmd_args += controller.script_arguments.split(/\s+/)
    end
    cmd_args << controller.hostname

    command_line = cmd_args.map { |a| a.include?(' ') ? "\"#{a}\"" : a }.join(' ')

    log = controller.access_controller_logs.create!(
      action: 'backup',
      command_line: command_line,
      status: 'running'
    )

    env = build_env(controller)
    payload = AccessControllerPayloadBuilder.call

    stdout, stderr, status = Open3.capture3(env, *cmd_args, stdin_data: payload)
    output = [stdout, stderr].map(&:to_s).map(&:strip).reject(&:blank?).join("\n")

    log_status = status.success? ? 'success' : 'failed'
    log.update!(
      output: output.presence,
      exit_code: status.exitstatus,
      status: log_status
    )

    controller.record_backup_result!(log_status)
  rescue StandardError => e
    error_message = "Backup failed: #{e.class}: #{e.message}"

    if defined?(log) && log&.persisted?
      log.update!(output: error_message, status: 'failed')
    end

    controller.record_backup_result!('failed')
  end

  def build_env(controller)
    env = {}
    env.merge!(controller.parsed_environment_variables)
    env['ACCESS_TOKEN'] = controller.access_token if controller.access_token.present?
    env['ACCESS_CONTROLLER_NICKNAME'] = controller.nickname if controller.nickname.present?
    env['SYSLOG_SERVER'] = ENV['SYSLOG_SERVER'] if ENV['SYSLOG_SERVER'].present?
    env['SYSLOG_PORT'] = ENV['SYSLOG_PORT'] if ENV['SYSLOG_PORT'].present?
    env
  end
end
