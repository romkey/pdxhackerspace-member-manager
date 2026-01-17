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

    payload = build_payload
    env = build_env(type)

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

  def build_payload
    users = User.active.includes(:rfids, trainings_as_trainee: :training_topic)

    data = users.map do |user|
      {
        name: user.full_name.presence || user.display_name,
        uid: user.authentik_id.presence || user.id,
        greeting_name: user.greeting_name,
        rfids: user.rfids.map(&:rfid),
        permissions: user.trainings_as_trainee.map { |training| training.training_topic&.name }.compact.uniq
      }
    end

    JSON.generate(data)
  end

  def build_env(access_controller_type)
    env = {}
    if access_controller_type.access_token.present?
      env['ACCESS_TOKEN'] = access_controller_type.access_token
    end
    env
  end
end
