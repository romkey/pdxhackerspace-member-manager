namespace :authentik do
  desc 'Sync users from the configured Authentik group'
  task sync_users: :environment do
    count = Authentik::GroupSynchronizer.new.call
    puts "Synced #{count} Authentik users."
  end
end
