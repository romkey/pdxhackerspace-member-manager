namespace :recharge do
  desc 'Backfill historical subscription events from Recharge API into PaymentEvents. ' \
       'Only creates events — does not change membership status. ' \
       'Usage: rake recharge:backfill_subscriptions[365] (days to look back, default 1825 / ~5 years)'
  task :backfill_subscriptions, [:days] => :environment do |_t, args|
    days = (args[:days] || 1825).to_i
    lookback = days.days

    puts "Fetching subscription history from Recharge (#{days} days back)..."
    puts "This is history-only mode: creating PaymentEvents without changing membership status.\n\n"

    sync = Recharge::SubscriptionSynchronizer.new(lookback: lookback, history_only: true)
    stats = sync.call

    puts "\nDone!"
    puts "  #{stats[:created]} subscription_started events created"
    puts "  #{stats[:cancelled]} subscription_cancelled events created"
    puts "  #{stats[:skipped]} skipped (already existed or no matching user)"
  end

  desc 'Run subscription sync with a custom lookback. ' \
       'Unlike backfill, this DOES update membership status. ' \
       'Usage: rake recharge:subscription_sync[30] (days to look back, default 2 / 48 hours)'
  task :subscription_sync, [:days] => :environment do |_t, args|
    days = (args[:days] || 2).to_i
    lookback = days.days

    puts "Running subscription sync (#{days} days back)..."

    sync = Recharge::SubscriptionSynchronizer.new(lookback: lookback)
    stats = sync.call

    puts "\nDone!"
    puts "  #{stats[:created]} activated"
    puts "  #{stats[:cancelled]} cancelled"
    puts "  #{stats[:skipped]} skipped"
  end
end
