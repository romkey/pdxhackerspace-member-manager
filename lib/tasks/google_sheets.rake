namespace :google_sheets do
  desc 'Sync Google Sheet entries'
  task sync: :environment do
    if GoogleSheetsConfig.enabled?
      GoogleSheets::SyncJob.perform_now
      puts 'Google Sheets sync completed.'
    else
      puts 'Google Sheets credentials not configured; skipping.'
    end
  end
end

namespace :paypal do
  desc 'Sync PayPal payments'
  task sync_payments: :environment do
    if PaypalConfig.enabled?
      Paypal::PaymentSyncJob.perform_now
      puts 'PayPal payment sync completed.'
    else
      puts 'PayPal credentials not configured; skipping.'
    end
  end
end

namespace :recharge do
  desc 'Sync Recharge payments'
  task sync_payments: :environment do
    if RechargeConfig.enabled?
      Recharge::PaymentSyncJob.perform_now
      puts 'Recharge payment sync completed.'
    else
      puts 'Recharge credentials not configured; skipping.'
    end
  end
end
