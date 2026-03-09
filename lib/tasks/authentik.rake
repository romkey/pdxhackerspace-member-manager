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

      webhook_url = ENV.fetch('MEMBER_MANAGER_BASE_URL', nil)
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
        authentik_webhook = IncomingWebhook.find_by(type: 'authentik')
        slug = authentik_webhook&.slug || 'authentik'
        puts "Webhook URL: #{webhook_url}/webhooks/#{slug}"
      else
        puts "ERROR: Setup failed - #{result[:error]}"
        exit 1
      end
    end

    desc 'Create expression policies in Authentik for all existing application groups'
    task setup_group_policies: :environment do
      puts 'Setting up Authentik expression policies for existing application groups...'
      puts

      groups = ApplicationGroup.all
      if groups.empty?
        puts 'No application groups found.'
        exit 0
      end

      client = Authentik::Client.new
      created = 0
      updated = 0
      errors = 0

      groups.find_each do |group|
        policy_name = group.policy_name
        expression = group.policy_expression

        begin
          existing = client.find_expression_policy_by_name(policy_name)
          if existing
            policy_id = existing['pk']
            client.update_expression_policy(policy_id, expression: expression)
            group.update_column(:authentik_policy_id, policy_id) if group.authentik_policy_id != policy_id
            puts "  UPDATE #{group.name} -> #{policy_name} (#{policy_id})"
            updated += 1
          else
            result = client.create_expression_policy(name: policy_name, expression: expression)
            policy_id = result['pk']
            group.update_column(:authentik_policy_id, policy_id)
            puts "  CREATE #{group.name} -> #{policy_name} (#{policy_id})"
            created += 1
          end
        rescue StandardError => e
          puts "  ERROR #{group.name}: #{e.message}"
          errors += 1
        end
      end

      puts
      puts "Done: #{created} created, #{updated} updated, #{errors} errors."
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
