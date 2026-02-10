require 'open3'

class AccessControllerPingJob < ApplicationJob
  queue_as :default

  # Pings all enabled access controllers that have a "ping" action.
  # Updates each controller's ping_status based on the result.
  def perform
    AccessController.enabled.includes(:access_controller_type).find_each do |controller|
      type = controller.access_controller_type
      next unless type&.enabled?
      next unless Array(type.actions).map(&:to_s).include?('ping')

      ping_single(controller, type)
    end
  end

  private

  def ping_single(controller, type)
    script_path = type.script_path.to_s.strip
    return if script_path.blank?

    cmd_args = [script_path, 'ping']
    if controller.script_arguments.present?
      cmd_args += controller.script_arguments.split(/\s+/)
    end
    cmd_args << controller.hostname

    command_line = cmd_args.map { |a| a.include?(' ') ? "\"#{a}\"" : a }.join(' ')

    log = controller.access_controller_logs.create!(
      action: 'ping',
      command_line: command_line,
      status: 'running'
    )

    env = build_env(controller)

    stdout, stderr, status = Open3.capture3(env, *cmd_args, stdin_data: '')
    output = [stdout, stderr].map(&:to_s).map(&:strip).reject(&:blank?).join("\n")

    log_status = status.success? ? 'success' : 'failed'
    log.update!(
      output: output.presence,
      exit_code: status.exitstatus,
      status: log_status
    )

    controller.update!(
      ping_status: log_status,
      last_ping_at: Time.current
    )
  rescue StandardError => e
    error_message = "Ping failed: #{e.class}: #{e.message}"

    if defined?(log) && log&.persisted?
      log.update!(output: error_message, status: 'failed')
    end

    controller.update!(
      ping_status: 'failed',
      last_ping_at: Time.current
    )
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
