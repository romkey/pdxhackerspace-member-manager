require 'open3'

class AccessControllerVerbJob < ApplicationJob
  queue_as :default

  def perform(access_controller_id, action, user_id = nil)
    access_controller = AccessController.includes(:access_controller_type).find(access_controller_id)
    return unless access_controller.enabled?

    type = access_controller.access_controller_type
    return unless type&.enabled?

    script_path = type.script_path.to_s.strip
    return if script_path.blank?

    # Build command line arguments
    cmd_args = [script_path, action]
    if access_controller.script_arguments.present?
      cmd_args += access_controller.script_arguments.split(/\s+/)
    end
    cmd_args << access_controller.hostname

    command_line = cmd_args.map { |a| a.include?(' ') ? "\"#{a}\"" : a }.join(' ')

    # Create log entry
    log = access_controller.access_controller_logs.create!(
      action: action,
      command_line: command_line,
      status: 'running'
    )

    env = build_env(access_controller, user_id)

    payload = AccessControllerPayloadBuilder.call
    stdout, stderr, status = Open3.capture3(env, *cmd_args, stdin_data: payload)
    output = [stdout, stderr].map(&:to_s).map(&:strip).reject(&:blank?).join("\n")

    log_status = status.success? ? 'success' : 'failed'
    log.update!(
      output: output.presence,
      exit_code: status.exitstatus,
      status: log_status
    )

    access_controller.update!(
      last_command: action,
      last_command_at: Time.current,
      last_command_status: log_status,
      last_command_output: output.presence || "Command exited with status #{status.exitstatus}."
    )
  rescue StandardError => e
    error_message = "Command failed: #{e.class}: #{e.message}"

    if defined?(log) && log.persisted?
      log.update!(output: error_message, status: 'failed')
    end

    access_controller&.update!(
      last_command: action,
      last_command_at: Time.current,
      last_command_status: 'failed',
      last_command_output: error_message
    )
  end

  private

  def build_env(access_controller, user_id)
    env = {}
    env['ACCESS_TOKEN'] = access_controller.access_token if access_controller.access_token.present?
    env['ACCESS_CONTROLLER_NICKNAME'] = access_controller.nickname if access_controller.nickname.present?

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
