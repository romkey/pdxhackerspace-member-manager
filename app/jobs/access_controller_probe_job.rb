require 'open3'

class AccessControllerProbeJob < ApplicationJob
  queue_as :default

  def perform(access_controller_type_id)
    access_controller_type = AccessControllerType.find(access_controller_type_id)
    script_path = access_controller_type.script_path.to_s.strip
    return if script_path.blank?

    stdout, stderr, status = Open3.capture3(script_path, '--verbs')
    output = [stdout, stderr].map(&:to_s).join("\n")

    return unless status.success?

    verbs = output.split(/[\r\n,]+/).map(&:strip).reject(&:blank?).uniq.sort
    access_controller_type.update!(verbs: verbs)
  rescue StandardError => e
    Rails.logger.error("AccessControllerProbeJob failed for type #{access_controller_type_id}: #{e.message}")
  end
end
