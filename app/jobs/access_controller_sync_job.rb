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

    payload = AccessControllerPayloadBuilder.call
    env = build_env(access_controller)

    stdout, stderr, status = Open3.capture3(env, script_path, access_controller.hostname, stdin_data: payload)
    output = [stdout, stderr].map(&:to_s).map(&:strip).reject(&:blank?).join("\n")

    if status.success?
      access_controller.record_sync_success!(output.presence)
    else
      message = output.presence || "Sync failed with exit code #{status.exitstatus}."
      access_controller.record_sync_failure!(message)
    end
  rescue StandardError => e
    access_controller&.record_sync_failure!("Sync failed: #{e.class}: #{e.message}")
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
