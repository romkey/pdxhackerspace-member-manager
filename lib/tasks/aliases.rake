# frozen_string_literal: true

namespace :aliases do
  desc 'Backfill user aliases from linked PayPal, Recharge, Slack, Sheet, KoFi, and Authentik entries'
  task backfill: :environment do
    total_added = 0

    puts 'Scanning linked PayPal payments...'
    PaypalPayment.where.not(user_id: nil).where.not(payer_name: [nil, '']).find_each do |payment|
      user = payment.user
      next unless user

      if user.add_alias(payment.payer_name)
        user.save!
        total_added += 1
        puts "  + #{user.display_name}: added PayPal alias '#{payment.payer_name}'"
      end
    end

    puts 'Scanning linked Recharge payments...'
    RechargePayment.where.not(user_id: nil).where.not(customer_name: [nil, '']).find_each do |payment|
      user = payment.user
      next unless user

      if user.add_alias(payment.customer_name)
        user.save!
        total_added += 1
        puts "  + #{user.display_name}: added Recharge alias '#{payment.customer_name}'"
      end
    end

    puts 'Scanning linked Slack users...'
    SlackUser.where.not(user_id: nil).find_each do |slack_user|
      user = slack_user.user
      next unless user

      [slack_user.real_name, slack_user.display_name].compact_blank.each do |name|
        if user.add_alias(name)
          user.save!
          total_added += 1
          puts "  + #{user.display_name}: added Slack alias '#{name}'"
        end
      end
    end

    puts 'Scanning linked Sheet entries...'
    SheetEntry.where.not(user_id: nil).find_each do |entry|
      user = entry.user
      next unless user

      [entry.name, entry.alias_name, entry.paypal_name].compact_blank.each do |name|
        if user.add_alias(name)
          user.save!
          total_added += 1
          puts "  + #{user.display_name}: added Sheet alias '#{name}'"
        end
      end
    end

    puts 'Scanning linked KoFi payments...'
    KofiPayment.where.not(user_id: nil).where.not(from_name: [nil, '']).find_each do |payment|
      user = payment.user
      next unless user

      if user.add_alias(payment.from_name)
        user.save!
        total_added += 1
        puts "  + #{user.display_name}: added KoFi alias '#{payment.from_name}'"
      end
    end

    puts 'Scanning linked Authentik users...'
    AuthentikUser.where.not(user_id: nil).where.not(full_name: [nil, '']).find_each do |authentik_user|
      user = authentik_user.user
      next unless user

      if user.add_alias(authentik_user.full_name)
        user.save!
        total_added += 1
        puts "  + #{user.display_name}: added Authentik alias '#{authentik_user.full_name}'"
      end
    end

    puts "\nDone! Added #{total_added} aliases."
  end
end
