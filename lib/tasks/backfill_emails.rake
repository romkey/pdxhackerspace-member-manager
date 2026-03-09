namespace :emails do
  desc 'Preview copying email addresses from payments into members with no email'
  task preview: :environment do
    EmailBackfiller.new(dry_run: true).run
  end

  desc 'Copy email addresses from payments into members with no email'
  task backfill: :environment do
    EmailBackfiller.new(dry_run: false).run
  end
end

class EmailBackfiller
  def initialize(dry_run: true)
    @dry_run = dry_run
    @updated = 0
    @skipped_no_email = 0
    @skipped_conflict = 0
    @already_has_email = 0
  end

  def run
    puts "#{'[DRY RUN] ' if @dry_run}Finding members with payments but no email address..."
    puts

    User.where(email: [nil, '']).find_each do |user|
      email = find_email_from_payments(user)

      unless email
        @skipped_no_email += 1
        next
      end

      existing = User.where('LOWER(email) = ?', email.downcase).where.not(id: user.id).exists?
      if existing
        @skipped_conflict += 1
        puts "  SKIPPING #{user.display_name} (id: #{user.id}): #{email} already belongs to another member"
        next
      end

      @updated += 1
      puts "  #{@dry_run ? 'WOULD SET' : 'SETTING'} #{user.display_name} (id: #{user.id}): email -> #{email}"

      user.update!(email: email) unless @dry_run
    end

    puts
    puts 'Summary:'
    puts "  #{@dry_run ? 'Would update' : 'Updated'}: #{@updated}"
    puts "  Skipped (no email in payments): #{@skipped_no_email}"
    puts "  Skipped (email belongs to another member): #{@skipped_conflict}"
  end

  private

  def find_email_from_payments(user)
    # Check PayPal payments
    paypal_email = user.paypal_payments
                       .where.not(payer_email: [nil, ''])
                       .order(transaction_time: :desc)
                       .pick(:payer_email)
    return paypal_email.strip.downcase if paypal_email.present?

    # Check Recharge payments
    recharge_email = user.recharge_payments
                         .where.not(customer_email: [nil, ''])
                         .order(processed_at: :desc)
                         .pick(:customer_email)
    return recharge_email.strip.downcase if recharge_email.present?

    # Check Ko-fi payments
    kofi_email = KofiPayment.where(user_id: user.id)
                            .where.not(email: [nil, ''])
                            .order(created_at: :desc)
                            .pick(:email)
    return kofi_email.strip.downcase if kofi_email.present?

    nil
  end
end
