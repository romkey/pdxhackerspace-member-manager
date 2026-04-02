# frozen_string_literal: true

# Encapsulate cleanup logic for rake tasks membership:cleanup / preview_cleanup.
# rubocop:disable Rails/Output, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
# STDOUT is deliberate for operator-facing rake output; complexity mirrors legacy rake definition.
class MembershipCleanup
  def initialize(dry_run:)
    @dry_run = dry_run
    @plans = MembershipPlan.primary.to_a
    @changes = { plan_matched: [], payment_type_set: [], marked_paying: [],
                 marked_lapsed: [], marked_inactive: [], marked_sponsored_active: [],
                 skipped_service: [], no_change: [] }
  end

  def run
    puts @dry_run ? 'PREVIEW — no changes will be made' : 'Membership Cleanup'
    puts '=' * 60
    puts ''
    puts 'Membership plans available for matching:'
    @plans.each { |p| puts "  - #{p.name}: $#{format('%.2f', p.cost)} (#{p.billing_frequency})" }
    puts ''

    User.non_service_accounts.includes(:paypal_payments, :recharge_payments, :sheet_entry, :membership_plan)
        .find_each do |user|
      process_user(user)
    end

    skipped = User.service_accounts.count
    puts ''
    puts "Skipped #{skipped} service accounts"
    puts ''
    print_summary
    puts ''
    puts @dry_run ? "Run 'rake membership:cleanup' to apply these changes." : 'Done!'
  end

  private

  def process_user(user)
    actions = []

    all_payments = collect_payments(user)
    latest = all_payments.last

    # 1. Sponsored users — always active (check is_sponsored flag, membership_status, or sheet entry)
    if user.is_sponsored? || user.membership_status == 'sponsored' ||
       user.sheet_entry&.status.to_s.downcase.include?('sponsored')
      if user.membership_status != 'sponsored' || user.payment_type != 'sponsored' || user.dues_status != 'current'
        apply(user, membership_status: 'sponsored', payment_type: 'sponsored', dues_status: 'current')
        actions << 'set sponsored/active'
        @changes[:marked_sponsored_active] << user
      end
      @changes[:no_change] << user if actions.empty?
      return
    end

    # 2. No payments and not sponsored → inactive
    if all_payments.empty?
      if user.dues_status != 'inactive' || user.membership_status == 'paying'
        new_status = user.membership_status == 'paying' ? 'unknown' : user.membership_status
        apply(user, dues_status: 'inactive', membership_status: new_status)
        actions << 'no payments → inactive'
        @changes[:marked_inactive] << user
      end
      @changes[:no_change] << user if actions.empty?
      return
    end

    # 3. Has payments — match plan if missing
    if user.membership_plan_id.blank? && latest[:amount].present?
      matched = MembershipTaskHelpers.find_matching_plan(@plans, latest[:amount])
      if matched
        apply(user, membership_plan_id: matched.id)
        actions << "matched plan: #{matched.name}"
        @changes[:plan_matched] << { user: user, plan: matched }
      end
    end

    # Determine effective plan (may have just been set, or was already present)
    effective_plan = if user.membership_plan_id.present?
                       user.membership_plan || MembershipPlan.find_by(id: user.membership_plan_id)
                     elsif latest[:amount].present?
                       MembershipTaskHelpers.find_matching_plan(@plans, latest[:amount])
                     end

    # 4. Has payments but no payment_type → set from payment source
    if %w[unknown inactive].include?(user.payment_type)
      apply(user, payment_type: latest[:type])
      actions << "payment_type → #{latest[:type]}"
      @changes[:payment_type_set] << { user: user, type: latest[:type] }
    end

    # 5. Check freshness against plan billing period
    cutoff = MembershipTaskHelpers.cutoff_for_plan(effective_plan)

    dues_at = User.dues_due_at_from_payment_cycle(latest[:time].to_date, effective_plan)

    if latest[:time] >= cutoff
      # Current
      if user.membership_status != 'paying' || user.dues_status != 'current'
        apply(user, membership_status: 'paying', dues_status: 'current', dues_due_at: dues_at)
        actions << 'paying + current'
        @changes[:marked_paying] << user
      end
    elsif user.dues_status != 'lapsed'
      # Lapsed
      apply(user, dues_status: 'lapsed', dues_due_at: dues_at)
      actions << "lapsed (last payment #{latest[:time].to_date})"
      @changes[:marked_lapsed] << user
    end

    if actions.any?
      plan_label = if effective_plan
                     "#{effective_plan.name} (#{effective_plan.billing_frequency})"
                   else
                     'no plan (monthly default)'
                   end
      puts "  #{user.display_name}: #{actions.join(', ')} [#{plan_label}]"
    else
      @changes[:no_change] << user
    end
  end

  def collect_payments(user)
    payments = []
    user.paypal_payments.each do |p|
      next if p.transaction_time.blank?

      payments << { time: p.transaction_time, amount: p.amount, type: 'paypal' }
    end
    user.recharge_payments.each do |p|
      next if p.processed_at.blank?

      payments << { time: p.processed_at, amount: p.amount, type: 'recharge' }
    end
    KofiPayment.where(user_id: user.id).find_each do |p|
      next if p.timestamp.blank?

      payments << { time: p.timestamp, amount: p.amount, type: 'kofi' }
    end
    payments.sort_by { |p| p[:time] }
  end

  def apply(user, attrs)
    return if @dry_run

    # Use save! so the compute_active_status callback runs
    attrs.each { |k, v| user.send(:"#{k}=", v) }
    user.save!
  end

  def print_summary
    puts '=' * 60
    puts 'Summary:'
    puts "  Plan matched:           #{@changes[:plan_matched].size}"
    @changes[:plan_matched].each { |h| puts "    #{h[:user].display_name} → #{h[:plan].name}" }
    puts "  Payment type set:       #{@changes[:payment_type_set].size}"
    @changes[:payment_type_set].each { |h| puts "    #{h[:user].display_name} → #{h[:type]}" }
    puts "  Marked paying+current:  #{@changes[:marked_paying].size}"
    puts "  Marked lapsed:          #{@changes[:marked_lapsed].size}"
    @changes[:marked_lapsed].each { |u| puts "    #{u.display_name}" }
    puts "  Marked inactive:        #{@changes[:marked_inactive].size}"
    @changes[:marked_inactive].first(20).each { |u| puts "    #{u.display_name}" }
    puts "    ... and #{@changes[:marked_inactive].size - 20} more" if @changes[:marked_inactive].size > 20
    puts "  Confirmed sponsored:    #{@changes[:marked_sponsored_active].size}"
    puts "  No change needed:       #{@changes[:no_change].size}"
  end
end
# rubocop:enable Rails/Output, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
