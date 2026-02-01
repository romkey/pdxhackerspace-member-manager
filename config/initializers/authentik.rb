Rails.application.config.x.authentik = ActiveSupport::InheritableOptions.new(
  issuer: ENV["AUTHENTIK_ISSUER"],
  client_id: ENV["AUTHENTIK_CLIENT_ID"],
  client_secret: ENV["AUTHENTIK_CLIENT_SECRET"],
  redirect_uri: ENV["AUTHENTIK_REDIRECT_URI"],
  group_id: ENV["AUTHENTIK_GROUP_ID"],
  api_base_url: ENV["AUTHENTIK_API_BASE_URL"] || ENV["AUTHENTIK_ISSUER"],
  api_token: ENV["AUTHENTIK_API_TOKEN"],
  group_page_size: ENV.fetch("AUTHENTIK_GROUP_PAGE_SIZE", 200).to_i,
  webhook_secret: ENV["AUTHENTIK_WEBHOOK_SECRET"],
  synced_group_ids: ENV["AUTHENTIK_SYNCED_GROUP_IDS"]&.split(',')&.map(&:strip) || []
)

module AuthentikConfig
  def self.settings
    Rails.application.config.x.authentik
  end

  def self.enabled_for_login?
    settings.client_id.present? && settings.client_secret.present? && settings.issuer.present?
  end
end


