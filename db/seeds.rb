if LocalAuthConfig.enabled? && LocalAuthConfig.settings.default_email.present?
  account = LocalAccount.find_or_initialize_by(email: LocalAuthConfig.settings.default_email)
  password = LocalAuthConfig.settings.default_password || SecureRandom.base58(24)

  account.assign_attributes(
    full_name: LocalAuthConfig.settings.default_full_name,
    password: password,
    password_confirmation: password,
    admin: true,
    active: true
  )

  if account.new_record?
    account.save!
    Rails.logger.debug { "Local admin created: #{account.email} / #{password}" }
  elsif account.changed?
    account.save!
    Rails.logger.debug { "Local admin updated: #{account.email}" }
  else
    Rails.logger.debug { "Local admin already present: #{account.email}" }
  end
else
  Rails.logger.debug 'Local auth disabled or missing credentials; skipping local admin seed.'
end

# Seed training topics
training_topics = [
  'Laser',
  'Sewing Machine',
  'Serger',
  'Embroidery Machine',
  'Dremel 3D45',
  'Ender 3',
  'Prusa',
  'Laminator',
  'Shaper',
  'General Shop',
  'Event Host',
  'Vinyl Cutter',
  'MPCNC Marlin',
  'Long Mill',
  'Member Management'
]

training_topics.each do |topic_name|
  TrainingTopic.find_or_create_by!(name: topic_name)
end

Rails.logger.debug { "Seeded #{training_topics.count} training topics." }

# Seed email templates
EmailTemplate.seed_defaults!
Rails.logger.debug { "Seeded #{EmailTemplate.count} email templates." }

# Seed payment processors
PaymentProcessor.seed_defaults!
Rails.logger.debug { "Seeded #{PaymentProcessor.count} payment processors." }
