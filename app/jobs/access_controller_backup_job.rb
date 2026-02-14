require 'open3'

# Runs the backup action on all enabled access controllers sequentially.
# Scheduled via sidekiq-cron to run daily at 1 AM.
class AccessControllerBackupJob < ApplicationJob
  queue_as :default

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

    cmd_args = build_command_args(script_path, controller)
    log = create_backup_log(controller, cmd_args)
    execute_backup(controller, cmd_args, log)
  rescue StandardError => e
    handle_backup_error(controller, log, e)
  end

  def build_command_args(script_path, controller)
    args = [script_path, 'backup']
    args += controller.script_arguments.split(/\s+/) if controller.script_arguments.present?
    args << controller.hostname
    args
  end

  def create_backup_log(controller, cmd_args)
    command_line = cmd_args.map { |a| a.include?(' ') ? "\"#{a}\"" : a }.join(' ')
    controller.access_controller_logs.create!(
      action: 'backup', command_line: command_line, status: 'running'
    )
  end

  def execute_backup(controller, cmd_args, log)
    env = build_env(controller)
    payload = AccessControllerPayloadBuilder.call
    stdout, stderr, status = Open3.capture3(env, *cmd_args, stdin_data: payload)
    output = [stdout, stderr].map(&:to_s).map(&:strip).compact_blank.join("\n")
    log_status = status.success? ? 'success' : 'failed'

    log.update!(output: output.presence, exit_code: status.exitstatus, status: log_status)
    controller.record_backup_result!(log_status)
  end

  def handle_backup_error(controller, log, error)
    message = "Backup failed: #{error.class}: #{error.message}"
    log&.update!(output: message, status: 'failed') if log&.persisted?
    controller.record_backup_result!('failed')
  end

  def build_env(controller)
    env = controller.parsed_environment_variables.dup
    add_env_if_present(env, 'ACCESS_TOKEN', controller.access_token)
    add_env_if_present(env, 'ACCESS_CONTROLLER_NICKNAME', controller.nickname)
    add_env_if_present(env, 'SYSLOG_SERVER', ENV.fetch('SYSLOG_SERVER', nil))
    add_env_if_present(env, 'SYSLOG_PORT', ENV.fetch('SYSLOG_PORT', nil))
    env
  end

  def add_env_if_present(env, key, value)
    env[key] = value if value.present?
  end
end
