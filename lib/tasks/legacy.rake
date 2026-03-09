namespace :legacy do
  desc 'Preview which members would be marked as legacy (dry run, no changes)'
  task preview: :environment do
    LegacyMarker.new(dry_run: true).run
  end

  desc 'Mark members with no payment history as legacy'
  task mark: :environment do
    LegacyMarker.new(dry_run: false).run
  end
end

class LegacyMarker
  def initialize(dry_run: true)
    @dry_run = dry_run
    @marked_count = 0
    @skipped_count = 0
    @already_legacy_count = 0
  end

  def run
    puts "#{'[DRY RUN] ' if @dry_run}Scanning members for legacy status..."
    puts

    User.non_service_accounts.find_each do |user|
      if user.legacy?
        @already_legacy_count += 1
        next
      end

      if should_mark_legacy?(user)
        @marked_count += 1
        reason = build_reason(user)
        action = @dry_run ? 'WOULD MARK' : 'MARKING'
        puts "  #{action} legacy: #{user.display_name} (#{user.email || 'no email'}) — #{reason}"
        user.update!(legacy: true) unless @dry_run
      else
        @skipped_count += 1
      end
    end

    puts
    puts 'Summary:'
    puts "  Already legacy: #{@already_legacy_count}"
    puts "  #{@dry_run ? 'Would mark' : 'Marked'} as legacy: #{@marked_count}"
    puts "  Skipped (have payment info): #{@skipped_count}"
  end

  private

  def should_mark_legacy?(user)
    # Skip active paying members
    return false if user.membership_status == 'paying' && user.dues_status == 'current'

    # Skip sponsored members (check flag, membership status, and payment type)
    return false if user.is_sponsored?
    return false if user.membership_status == 'sponsored'
    return false if user.payment_type == 'sponsored'

    # Skip guests
    return false if user.membership_status == 'guest'

    # Check for any payment records
    has_paypal = user.paypal_payments.exists?
    has_recharge = user.recharge_payments.exists?
    has_kofi = KofiPayment.exists?(user_id: user.id)
    has_payment_date = user.last_payment_date.present? || user.recharge_most_recent_payment_date.present?

    # If they have any payment info, they're not legacy
    return false if has_paypal || has_recharge || has_kofi || has_payment_date

    # No payment info at all — mark as legacy
    true
  end

  def build_reason(user)
    parts = []
    parts << "status: #{user.membership_status}"
    parts << "dues: #{user.dues_status}"
    parts << 'no payment records'
    unless user.last_payment_date.present? || user.recharge_most_recent_payment_date.present?
      parts << 'no payment dates'
    end
    parts.join(', ')
  end
end
