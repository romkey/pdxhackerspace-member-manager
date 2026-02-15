# frozen_string_literal: true

namespace :aliases do
  desc 'Backfill user aliases from linked entries, then link unlinked entries via aliases'
  task backfill: :environment do
    total_added = backfill_aliases_from_linked_entries
    puts "\nPhase 1 complete: added #{total_added} aliases."

    total_linked = link_unlinked_entries_via_aliases
    puts "\nPhase 2 complete: linked #{total_linked} previously unlinked entries."

    # If we linked new entries, run alias collection again to pick up names from newly linked records
    if total_linked.positive?
      puts "\nPhase 3: re-scanning newly linked entries for additional aliases..."
      extra = backfill_aliases_from_linked_entries
      puts "Phase 3 complete: added #{extra} additional aliases."
    end

    puts "\nAll done!"
  end
end

# Phase 1: Collect aliases from all linked entries, batched per user to avoid duplicates.
def backfill_aliases_from_linked_entries # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
  # Collect candidate aliases per user_id: { user_id => Set of names }
  candidates = Hash.new { |h, k| h[k] = Set.new }

  puts 'Scanning linked PayPal payments...'
  PaypalPayment.where.not(user_id: nil).where.not(payer_name: [nil, '']).find_each do |p|
    candidates[p.user_id] << p.payer_name.strip
  end

  puts 'Scanning linked Recharge payments...'
  RechargePayment.where.not(user_id: nil).where.not(customer_name: [nil, '']).find_each do |p|
    candidates[p.user_id] << p.customer_name.strip
  end

  puts 'Scanning linked Slack users...'
  SlackUser.where.not(user_id: nil).find_each do |su|
    [su.real_name, su.display_name].compact_blank.each { |n| candidates[su.user_id] << n.strip }
  end

  puts 'Scanning linked Sheet entries...'
  SheetEntry.where.not(user_id: nil).find_each do |entry|
    [entry.name, entry.alias_name, entry.paypal_name].compact_blank.each { |n| candidates[entry.user_id] << n.strip }
  end

  puts 'Scanning linked KoFi payments...'
  KofiPayment.where.not(user_id: nil).where.not(from_name: [nil, '']).find_each do |p|
    candidates[p.user_id] << p.from_name.strip
  end

  puts 'Scanning linked Authentik users...'
  AuthentikUser.where.not(user_id: nil).where.not(full_name: [nil, '']).find_each do |au|
    candidates[au.user_id] << au.full_name.strip
  end

  # Now apply aliases in batch per user
  total_added = 0
  candidates.each do |user_id, names|
    user = User.find_by(id: user_id)
    next unless user

    added_any = false
    names.each do |name|
      if user.add_alias(name)
        added_any = true
        total_added += 1
        puts "  + #{user.display_name}: '#{name}'"
      end
    end
    user.save! if added_any
  end

  total_added
end

# Phase 2: Try to link unlinked entries using name/alias matching.
# Only links when exactly one user matches to avoid ambiguity.
def link_unlinked_entries_via_aliases # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
  total_linked = 0

  puts "\nLinking unlinked PayPal payments by name/alias..."
  PaypalPayment.where(user_id: nil).where.not(payer_name: [nil, '']).find_each do |payment|
    user = find_unique_user_by_name_or_email(payment.payer_name, payment.payer_email)
    if user
      payment.update!(user: user)
      total_linked += 1
      puts "  -> linked PayPal #{payment.paypal_id} ('#{payment.payer_name}') to #{user.display_name}"
    end
  end

  puts 'Linking unlinked Recharge payments by name/alias...'
  RechargePayment.where(user_id: nil).where.not(customer_name: [nil, '']).find_each do |payment|
    user = find_unique_user_by_name_or_email(payment.customer_name, payment.customer_email)
    if user
      payment.update!(user: user)
      total_linked += 1
      puts "  -> linked Recharge #{payment.recharge_id} ('#{payment.customer_name}') to #{user.display_name}"
    end
  end

  puts 'Linking unlinked Slack users by name/alias...'
  SlackUser.where(user_id: nil).where.not(real_name: [nil, '']).find_each do |slack_user|
    user = find_unique_user_by_name_or_email(slack_user.real_name, slack_user.email)
    if user
      slack_user.update!(user: user)
      total_linked += 1
      puts "  -> linked Slack @#{slack_user.username} ('#{slack_user.real_name}') to #{user.display_name}"
    end
  end

  puts 'Linking unlinked Sheet entries by name/alias...'
  SheetEntry.where(user_id: nil).where.not(name: [nil, '']).find_each do |entry|
    user = find_unique_user_by_name_or_email(entry.name, entry.email)
    if user
      entry.update!(user: user)
      total_linked += 1
      puts "  -> linked Sheet '#{entry.name}' to #{user.display_name}"
    end
  end

  puts 'Linking unlinked KoFi payments by name/alias...'
  KofiPayment.where(user_id: nil).where.not(from_name: [nil, '']).find_each do |payment|
    user = find_unique_user_by_name_or_email(payment.from_name, payment.email)
    if user
      payment.update!(user: user)
      total_linked += 1
      puts "  -> linked KoFi '#{payment.from_name}' to #{user.display_name}"
    end
  end

  total_linked
end

# Find a user by name/alias and optionally email. Returns the user only if exactly one match.
def find_unique_user_by_name_or_email(name, email = nil)
  matches = Set.new

  # Match by email (primary + extra_emails)
  if email.present?
    normalized_email = email.to_s.strip.downcase
    matches.merge(User.where('LOWER(email) = ?', normalized_email).to_a)
    matches.merge(
      User.where('EXISTS (SELECT 1 FROM unnest(extra_emails) AS e WHERE LOWER(e) = ?)', normalized_email).to_a
    )
  end

  # Match by name or alias
  matches.merge(User.by_name_or_alias(name).to_a) if name.present?

  # Only link if exactly one user matches
  return nil unless matches.size == 1

  matches.first
end
