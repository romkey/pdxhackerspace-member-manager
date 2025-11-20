namespace :slack do
  desc 'Sync users from Slack'
  task sync_users: :environment do
    Slack::UserSyncJob.perform_now
  end
end
