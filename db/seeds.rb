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
    puts "Local admin created: #{account.email} / #{password}"
  elsif account.changed?
    account.save!
    puts "Local admin updated: #{account.email}"
  else
    puts "Local admin already present: #{account.email}"
  end
else
  puts "Local auth disabled or missing credentials; skipping local admin seed."
end
