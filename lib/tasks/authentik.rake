namespace :authentik do
  desc 'Sync users from the configured Authentik group'
  task sync_users: :environment do
    count = Authentik::GroupSynchronizer.new.call
    puts "Synced #{count} Authentik users."
  end

  namespace :webhooks do
    desc 'Set up Authentik webhook notifications (creates transport, policies, and rules)'
    task setup: :environment do
      puts 'Setting up Authentik webhook configuration...'
      puts

      webhook_url = ENV['MEMBER_MANAGER_BASE_URL']
      if webhook_url.blank?
        puts 'ERROR: MEMBER_MANAGER_BASE_URL environment variable is required.'
        puts 'Set it to your MemberManager public URL (e.g., https://members.example.org)'
        exit 1
      end

      setup = Authentik::WebhookSetup.new
      result = setup.setup!

      if result[:success]
        puts 'SUCCESS: Webhook configuration completed!'
        puts
        puts "Transport: #{result[:transport]['name']} (#{result[:transport]['pk']})"
        puts "User Policy: #{result[:user_policy]['name']} (#{result[:user_policy]['pk']})"
        puts "Group Policy: #{result[:group_policy]['name']} (#{result[:group_policy]['pk']})"
        puts "Rule: #{result[:rule]['name']} (#{result[:rule]['pk']})"
        puts
        puts "Webhook URL: #{webhook_url}/webhooks/authentik"
      else
        puts "ERROR: Setup failed - #{result[:error]}"
        exit 1
      end
    end

    desc 'Show current Authentik webhook configuration status'
    task status: :environment do
      puts 'Checking Authentik webhook configuration status...'
      puts

      setup = Authentik::WebhookSetup.new
      status = setup.status

      if status[:configured]
        puts 'Status: CONFIGURED'
        puts
        puts "Transport: #{status[:transport][:name]} (#{status[:transport][:id]})"
        puts "  Webhook URL: #{status[:transport][:webhook_url]}"
        puts "User Policy: #{status[:user_policy][:name]} (#{status[:user_policy][:id]})" if status[:user_policy]
        puts "Group Policy: #{status[:group_policy][:name]} (#{status[:group_policy][:id]})" if status[:group_policy]
        puts "Rule: #{status[:rule][:name]} (#{status[:rule][:id]})"
      else
        puts 'Status: NOT CONFIGURED'
        puts
        puts 'Run `rails authentik:webhooks:setup` to configure webhooks.'
      end

      puts
      synced_groups = ApplicationGroup.with_authentik_group_id.includes(:application)
      if synced_groups.any?
        puts "Synced Groups (#{synced_groups.count}):"
        synced_groups.each do |group|
          puts "  - #{group.application.name} / #{group.name}: #{group.authentik_group_id}"
        end
      else
        puts 'Synced Groups: (all events - no Application Groups have Authentik Group IDs)'
        puts '  Set Authentik Group ID on Application Groups to filter events.'
      end
    end

    desc 'Remove Authentik webhook configuration (deletes transport, policies, and rules)'
    task teardown: :environment do
      puts 'Removing Authentik webhook configuration...'
      puts

      setup = Authentik::WebhookSetup.new
      result = setup.teardown!

      if result[:success]
        puts 'SUCCESS: Webhook configuration removed.'
      else
        puts "ERROR: Teardown failed - #{result[:error]}"
        exit 1
      end
    end
  end
end
