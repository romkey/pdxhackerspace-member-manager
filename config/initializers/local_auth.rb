Rails.application.config.x.local_auth = ActiveSupport::InheritableOptions.new(
  enabled: ActiveModel::Type::Boolean.new.cast(ENV.fetch("LOCAL_AUTH_ENABLED", "false")),
  default_email: ENV["LOCAL_AUTH_EMAIL"],
  default_password: ENV["LOCAL_AUTH_PASSWORD"],
  default_full_name: ENV["LOCAL_AUTH_FULL_NAME"] || "Local Admin"
)

module LocalAuthConfig
  def self.settings
    Rails.application.config.x.local_auth
  end

  def self.enabled?
    settings.enabled
  end
end

