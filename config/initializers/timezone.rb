# Set timezone from environment variable
timezone = ENV.fetch("TIMEZONE", "UTC")
Time.zone = timezone

# Also set TZ environment variable for system-level timezone
ENV["TZ"] = timezone

Rails.logger.info "Timezone configured: #{Time.zone.name} (#{Time.zone.now})"

