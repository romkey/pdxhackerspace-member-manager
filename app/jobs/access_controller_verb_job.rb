require 'open3'

class AccessControllerVerbJob < ApplicationJob
  queue_as :default

  def perform(access_controller_id, action)
    access_controller = AccessController.includes(:access_controller_type).find(access_controller_id)
    return unless access_controller.enabled?

    type = access_controller.access_controller_type
    return unless type&.enabled?

    script_path = type.script_path.to_s.strip
    return if script_path.blank?

    env = {}
    env['ACCESS_TOKEN'] = access_controller.access_token if access_controller.access_token.present?

    payload = AccessControllerPayloadBuilder.call
    stdout, stderr, status = Open3.capture3(env, script_path, action, access_controller.hostname, stdin_data: payload)
    output = [stdout, stderr].map(&:to_s).map(&:strip).reject(&:blank?).join("\n")

    access_controller.update!(
      last_command: action,
      last_command_at: Time.current,
      last_command_status: status.success? ? 'success' : 'failed',
      last_command_output: output.presence || "Command exited with status #{status.exitstatus}."
    )
  rescue StandardError => e
    access_controller&.update!(
      last_command: action,
      last_command_at: Time.current,
      last_command_status: 'failed',
      last_command_output: "Command failed: #{e.class}: #{e.message}"
    )
  end
end
