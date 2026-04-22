class ReportsController < AdminController
  include Pagy::Method

  LIMIT = 20

  def index
    @membership_status_unknown = User.where(membership_status: 'unknown',
                                            active: true).non_service_accounts.ordered_by_display_name.limit(LIMIT)
    @membership_status_unknown_count = User.where(membership_status: 'unknown', active: true).non_service_accounts.count
    @payment_type_unknown = User.where(payment_type: 'unknown',
                                       active: true).non_service_accounts.ordered_by_display_name.limit(LIMIT)
    @payment_type_unknown_count = User.where(payment_type: 'unknown', active: true).non_service_accounts.count
    @dues_status_unknown = User.where(dues_status: 'unknown',
                                      active: true).non_service_accounts.ordered_by_display_name.limit(LIMIT)
    @dues_status_unknown_count = User.where(dues_status: 'unknown', active: true).non_service_accounts.count
    @dues_status_lapsed = User.where(dues_status: 'lapsed',
                                     active: true).non_service_accounts.ordered_by_display_name.limit(LIMIT)
    @dues_status_lapsed_count = User.where(dues_status: 'lapsed', active: true).non_service_accounts.count

    # Lapsed members with access after lapse
    prepare_lapsed_with_access(limit: LIMIT)

    # Sponsored members who are also paying
    @sponsored_and_paying = User.where(is_sponsored: true, membership_status: 'paying')
                                .non_service_accounts
                                .non_legacy
                                .ordered_by_display_name
                                .limit(LIMIT)
    @sponsored_and_paying_count = User.where(is_sponsored: true, membership_status: 'paying')
                                      .non_service_accounts
                                      .non_legacy
                                      .count

    # Active members with no email
    @no_email = User.where(email: [nil, ''])
                    .where(membership_status: %w[paying sponsored guest])
                    .non_service_accounts
                    .non_legacy
                    .ordered_by_display_name
                    .limit(LIMIT)
    @no_email_count = User.where(email: [nil, ''])
                          .where(membership_status: %w[paying sponsored guest])
                          .non_service_accounts
                          .non_legacy
                          .count

    # Legacy members with access records
    prepare_legacy_with_access(limit: LIMIT)

    # Legacy members with recent (last year) access records
    prepare_legacy_recent_access(limit: LIMIT)

    # Inactive members with RFID cards who would lose access if sync_inactive_members is disabled
    inactive_rfid_ids = User.where(active: false)
                            .non_service_accounts
                            .joins(:rfids)
                            .distinct
                            .pluck(:id)
    @inactive_with_rfid = User.where(id: inactive_rfid_ids)
                              .includes(:rfids, :membership_plan)
                              .ordered_by_display_name
                              .limit(LIMIT)
    @inactive_with_rfid_count = inactive_rfid_ids.size

    # Paying members with fewer than 3 access log entries
    few_access_ids = User.where(membership_status: 'paying')
                         .non_service_accounts
                         .non_legacy
                         .left_joins(:access_logs)
                         .group('users.id')
                         .having('COUNT(access_logs.id) < 3')
                         .pluck('users.id')
    @no_access = User.where(id: few_access_ids).ordered_by_display_name.limit(LIMIT)
    @no_access_count = few_access_ids.size

    # Lapsed members with Slack accounts
    prepare_lapsed_with_slack(limit: LIMIT)

    # Legacy members with Slack accounts
    prepare_legacy_with_slack(limit: LIMIT)

    # Lapsed members still active on Slack
    prepare_lapsed_active_slack(limit: LIMIT)

    # Legacy members still active on Slack
    prepare_legacy_active_slack(limit: LIMIT)

    # Slack users inactive for over a year
    prepare_slack_inactive(limit: LIMIT)

    # Active members with no email
    prepare_active_no_email(limit: LIMIT)

    # Prepare chart data
    prepare_chart_data
  end

  def prepare_lapsed_with_access(limit: nil)
    # Find members whose dues have lapsed and who have access log entries after their last payment
    lapsed_users = User.where(dues_status: 'lapsed')
                       .where.not(membership_status: %w[banned deceased])
                       .non_service_accounts
                       .non_legacy
                       .includes(:access_logs)

    @lapsed_with_access = []

    lapsed_users.find_each do |user|
      last_payment = user.most_recent_payment_date
      next if last_payment.blank?

      # Find access logs after the last payment date
      accesses_after_lapse = user.access_logs.where('logged_at > ?', last_payment.end_of_day).order(logged_at: :desc)
      next unless accesses_after_lapse.exists?

      @lapsed_with_access << {
        user: user,
        last_payment_date: last_payment,
        access_count: accesses_after_lapse.count,
        most_recent_access: accesses_after_lapse.first,
        recent_accesses: accesses_after_lapse.limit(5)
      }
    end

    # Sort by most recent access descending
    @lapsed_with_access.sort_by! { |entry| entry[:most_recent_access].logged_at }.reverse!
    @lapsed_with_access_count = @lapsed_with_access.size
    @lapsed_with_access = @lapsed_with_access.first(limit) if limit
  end

  def prepare_legacy_with_access(limit: nil)
    legacy_with_access_users = User.where(legacy: true)
                                   .non_service_accounts
                                   .joins(:access_logs)
                                   .distinct
                                   .includes(:access_logs)

    @legacy_with_access = []

    legacy_with_access_users.find_each do |user|
      recent_accesses = user.access_logs.order(logged_at: :desc).limit(5)
      most_recent = recent_accesses.first
      next unless most_recent

      @legacy_with_access << {
        user: user,
        access_count: user.access_logs.count,
        most_recent_access: most_recent,
        recent_accesses: recent_accesses
      }
    end

    @legacy_with_access.sort_by! { |entry| entry[:most_recent_access].logged_at }.reverse!
    @legacy_with_access_count = @legacy_with_access.size
    @legacy_with_access = @legacy_with_access.first(limit) if limit
  end

  def prepare_legacy_recent_access(limit: nil)
    one_year_ago = 1.year.ago
    legacy_recent_users = User.where(legacy: true)
                              .non_service_accounts
                              .joins(:access_logs)
                              .where(access_logs: { logged_at: one_year_ago.. })
                              .distinct
                              .includes(:access_logs)

    @legacy_recent_access = []

    legacy_recent_users.find_each do |user|
      recent_accesses = user.access_logs.where(logged_at: one_year_ago..).order(logged_at: :desc).limit(10)
      most_recent = recent_accesses.first
      next unless most_recent

      @legacy_recent_access << {
        user: user,
        access_count: user.access_logs.where(logged_at: one_year_ago..).count,
        most_recent_access: most_recent,
        recent_accesses: recent_accesses
      }
    end

    @legacy_recent_access.sort_by! { |entry| entry[:most_recent_access].logged_at }.reverse!
    @legacy_recent_access_count = @legacy_recent_access.size
    @legacy_recent_access = @legacy_recent_access.first(limit) if limit
  end

  SLACK_JOIN_ORDER = Arel.sql(
    "LOWER(COALESCE(NULLIF(users.full_name, ''), " \
    "NULLIF(users.email, ''), users.authentik_id)) ASC"
  )

  def prepare_lapsed_with_slack(limit: nil)
    scope = User.where(dues_status: 'lapsed')
                .where.not(membership_status: %w[banned deceased])
                .non_service_accounts
                .non_legacy
                .joins(:slack_user)
                .includes(:slack_user)
                .order(SLACK_JOIN_ORDER)
    @lapsed_with_slack_count = scope.count
    @lapsed_with_slack = limit ? scope.limit(limit) : scope
  end

  def prepare_legacy_with_slack(limit: nil)
    scope = User.where(legacy: true)
                .non_service_accounts
                .joins(:slack_user)
                .includes(:slack_user)
                .order(SLACK_JOIN_ORDER)
    @legacy_with_slack_count = scope.count
    @legacy_with_slack = limit ? scope.limit(limit) : scope
  end

  def prepare_lapsed_active_slack(limit: nil)
    lapsed_with_slack = User.where(dues_status: 'lapsed')
                            .where.not(membership_status: %w[banned deceased])
                            .non_service_accounts
                            .non_legacy
                            .joins(:slack_user)
                            .where.not(slack_users: { last_active_at: nil })
                            .includes(:slack_user)

    @lapsed_active_slack = []
    lapsed_with_slack.find_each do |user|
      lapse_date = user.membership_ended_date || user.most_recent_payment_date
      next if lapse_date.blank?
      next unless user.slack_user.last_active_at > lapse_date.to_time.end_of_day

      @lapsed_active_slack << {
        user: user,
        slack_user: user.slack_user,
        lapse_date: lapse_date,
        last_slack_active: user.slack_user.last_active_at
      }
    end

    @lapsed_active_slack.sort_by! { |e| e[:last_slack_active] }.reverse!
    @lapsed_active_slack_count = @lapsed_active_slack.size
    @lapsed_active_slack = @lapsed_active_slack.first(limit) if limit
  end

  def prepare_legacy_active_slack(limit: nil)
    scope = User.where(legacy: true)
                .non_service_accounts
                .joins(:slack_user)
                .where.not(slack_users: { last_active_at: nil })
                .includes(:slack_user)
                .order('slack_users.last_active_at DESC')
    @legacy_active_slack_count = scope.count
    @legacy_active_slack = limit ? scope.limit(limit) : scope
  end

  def prepare_slack_inactive(limit: nil)
    one_year_ago = 1.year.ago
    scope = SlackUser.active
                     .where('last_active_at < ? OR last_active_at IS NULL', one_year_ago)
                     .order(Arel.sql('COALESCE(last_active_at, created_at) ASC'))
    @slack_inactive_count = scope.count
    @slack_inactive = limit ? scope.limit(limit) : scope
  end

  def prepare_active_no_email(limit: nil)
    scope = User.where(active: true)
                .where(email: [nil, ''])
                .ordered_by_display_name
    @active_no_email_count = scope.count
    @active_no_email = limit ? scope.limit(limit) : scope
  end

  def prepare_chart_data
    end_date = Time.current.end_of_month

    # Determine earliest date across all payment sources for full history
    earliest_paypal = PaypalPayment.where.not(transaction_time: nil).minimum(:transaction_time)
    earliest_recharge = RechargePayment.where.not(processed_at: nil).minimum(:processed_at)
    earliest_dates = [earliest_paypal, earliest_recharge].compact
    start_date = earliest_dates.any? ? earliest_dates.min.beginning_of_month : 12.months.ago.beginning_of_month

    # Build month list for the full range
    all_months = []
    cursor = start_date.to_date.beginning_of_month
    while cursor <= end_date.to_date
      all_months << cursor.strftime('%Y-%m')
      cursor = cursor.next_month
    end

    # Active members per month
    paypal_user_dates = PaypalPayment.joins(:user)
                                     .where(users: { active: true })
                                     .where.not(transaction_time: nil)
                                     .group('users.id')
                                     .minimum('paypal_payments.transaction_time')
    recharge_user_dates = RechargePayment.joins(:user)
                                         .where(users: { active: true })
                                         .where.not(processed_at: nil)
                                         .group('users.id')
                                         .minimum('recharge_payments.processed_at')
    user_earliest_payment = {}
    paypal_user_dates.each { |uid, d| user_earliest_payment[uid] = [user_earliest_payment[uid], d].compact.min }
    recharge_user_dates.each { |uid, d| user_earliest_payment[uid] = [user_earliest_payment[uid], d].compact.min }
    active_user_created = User.where(active: true).pluck(:id, :created_at).to_h

    active_members_data = {}
    all_months.each do |month_key|
      month_end = Date.parse("#{month_key}-01").end_of_month
      count = active_user_created.count do |user_id, created_at|
        ep = user_earliest_payment[user_id]
        (ep && ep <= month_end) || created_at <= month_end
      end
      active_members_data[month_key] = count
    end

    # Revenue per month (full history)
    paypal_by_month = Hash.new(0.0)
    PaypalPayment.where.not(transaction_time: nil).where.not(amount: nil).find_each do |p|
      paypal_by_month[p.transaction_time.strftime('%Y-%m')] += p.amount.to_f
    end
    recharge_by_month = Hash.new(0.0)
    RechargePayment.where.not(processed_at: nil).where.not(amount: nil).find_each do |p|
      recharge_by_month[p.processed_at.strftime('%Y-%m')] += p.amount.to_f
    end

    # Build structured data arrays for client-side pagination
    @active_members_chart_data = all_months.map { |m| { month: m, count: active_members_data[m] || 0 } }
    @revenue_chart_data = all_months.map do |m|
      { month: m, paypal: paypal_by_month[m].round(2), recharge: recharge_by_month[m].round(2) }
    end

    # New members and lapsed members per month (full history for client-side pagination)
    all_start_dates = User.where.not(membership_start_date: nil)
                          .non_service_accounts
                          .non_legacy
                          .pluck(:membership_start_date)
    all_end_dates = User.where.not(membership_ended_date: nil)
                        .non_service_accounts
                        .non_legacy
                        .pluck(:membership_ended_date)

    new_by_month = Hash.new(0)
    all_start_dates.each { |d| new_by_month[d.strftime('%Y-%m')] += 1 }

    lapsed_by_month = Hash.new(0)
    all_end_dates.each { |d| lapsed_by_month[d.strftime('%Y-%m')] += 1 }

    churn_months = (new_by_month.keys + lapsed_by_month.keys).uniq.sort
    @churn_data = churn_months.map do |m|
      { month: m, new_members: new_by_month[m], lapsed_members: lapsed_by_month[m] }
    end

    # Membership duration distribution for ended memberships
    ended_members = User.where.not(membership_start_date: nil)
                        .where.not(membership_ended_date: nil)
                        .non_service_accounts
                        .pluck(:membership_start_date, :membership_ended_date)

    @duration_total = ended_members.size
    duration_months = ended_members.map { |s, e| ((e - s).to_f / 30.44).round }

    buckets = {
      '< 1 month' => 0,
      '1-3 months' => 0,
      '3-6 months' => 0,
      '6-12 months' => 0,
      '1-2 years' => 0,
      '2-3 years' => 0,
      '3-5 years' => 0,
      '5+ years' => 0
    }

    duration_months.each do |m|
      case m
      when ...1 then buckets['< 1 month'] += 1
      when 1...3 then buckets['1-3 months'] += 1
      when 3...6 then buckets['3-6 months'] += 1
      when 6...12 then buckets['6-12 months'] += 1
      when 12...24 then buckets['1-2 years'] += 1
      when 24...36 then buckets['2-3 years'] += 1
      when 36...60 then buckets['3-5 years'] += 1
      else buckets['5+ years'] += 1
      end
    end

    @duration_labels = buckets.keys
    @duration_counts = buckets.values

    if duration_months.any?
      @duration_median = duration_months.sort[duration_months.size / 2]
      @duration_avg = (duration_months.sum.to_f / duration_months.size).round(1)
    else
      @duration_median = 0
      @duration_avg = 0
    end
  end

  def view_all
    @report_type = params[:report_type]

    case @report_type
    when 'membership-status-unknown'
      @users = User.where(membership_status: 'unknown', active: true).non_service_accounts.ordered_by_display_name
      @title = 'Membership Status: Unknown'
    when 'payment-type-unknown'
      @users = User.where(payment_type: 'unknown', active: true).non_service_accounts.ordered_by_display_name
      @title = 'Payment Type: Unknown'
    when 'dues-status-unknown'
      @users = User.where(dues_status: 'unknown', active: true).non_service_accounts.ordered_by_display_name
      @title = 'Dues Status: Unknown'
    when 'dues-status-lapsed'
      @users = User.where(dues_status: 'lapsed', active: true).non_service_accounts.ordered_by_display_name
      @title = 'Dues Status: Lapsed'
    when 'lapsed-with-access'
      prepare_lapsed_with_access
      @title = 'Lapsed Members with Access'
      render 'reports/lapsed_with_access_full'
      nil
    when 'no-email'
      @users = User.where(email: [nil, ''])
                   .where(membership_status: %w[paying sponsored guest])
                   .non_service_accounts
                   .non_legacy
                   .ordered_by_display_name
      @title = 'Members with No Email'
    when 'sponsored-and-paying'
      @users = User.where(is_sponsored: true, membership_status: 'paying')
                   .non_service_accounts
                   .non_legacy
                   .ordered_by_display_name
      @title = 'Sponsored & Paying Members'
    when 'no-access'
      few_access_ids = User.where(membership_status: 'paying')
                           .non_service_accounts
                           .non_legacy
                           .left_joins(:access_logs)
                           .group('users.id')
                           .having('COUNT(access_logs.id) < 3')
                           .pluck('users.id')
      @users = User.where(id: few_access_ids).ordered_by_display_name
      @title = 'Paying Members with Few Access Records'
    when 'inactive-with-rfid'
      ids = User.where(active: false)
                .non_service_accounts
                .joins(:rfids)
                .distinct
                .pluck(:id)
      @users = User.where(id: ids)
                   .includes(:rfids, :membership_plan)
                   .ordered_by_display_name
      @title = 'Inactive Members with RFID Access'
    when 'legacy-with-access'
      prepare_legacy_with_access
      @title = 'Legacy Members with Access'
      render 'reports/legacy_with_access_full'
      nil
    when 'legacy-recent-access'
      prepare_legacy_recent_access
      @title = 'Legacy Members with Recent Access'
      render 'reports/legacy_recent_access_full'
      nil
    when 'lapsed-with-slack'
      prepare_lapsed_with_slack
      @title = 'Lapsed Members with Slack Accounts'
      render 'reports/slack_members_full'
      nil
    when 'legacy-with-slack'
      prepare_legacy_with_slack
      @title = 'Legacy Members with Slack Accounts'
      render 'reports/slack_members_full'
      nil
    when 'lapsed-active-slack'
      prepare_lapsed_active_slack
      @title = 'Lapsed Members Still Active on Slack'
      render 'reports/slack_active_full'
      nil
    when 'legacy-active-slack'
      prepare_legacy_active_slack
      @title = 'Legacy Members Still Active on Slack'
      render 'reports/slack_members_full'
      nil
    when 'slack-inactive'
      prepare_slack_inactive
      @title = 'Slack Users Inactive for Over a Year'
      render 'reports/slack_inactive_full'
      nil
    when 'active-no-email'
      prepare_active_no_email
      @title = 'Active Members With No Email'
      render 'reports/active_no_email_full'
      nil
    else
      redirect_to reports_path, alert: 'Invalid report type.'
      nil
    end
  end

  def update_user
    user = User.find(params[:user_id])
    action_type = params[:action_type]
    anchor = params[:anchor] || params[:tab] || 'membership-status-unknown'

    case action_type
    when 'activate'
      if user.service_account?
        user.update!(active: true)
        notice = "#{user.display_name} activated."
      else
        notice = "Active status for #{user.display_name} is determined by membership and dues status."
      end
    when 'deactivate'
      if user.service_account?
        user.update!(active: false)
        notice = "#{user.display_name} deactivated."
      else
        notice = "Active status for #{user.display_name} is determined by membership and dues status."
      end
    when 'ban'
      user.update!(membership_status: 'banned')
      notice = "#{user.display_name} banned."
    when 'deceased'
      user.update!(membership_status: 'deceased')
      notice = "#{user.display_name} marked as deceased."
    when 'paying'
      user.update!(membership_status: 'paying')
      notice = "#{user.display_name} membership status set to paying."
    when 'sponsored'
      if anchor == 'payment-type-unknown'
        user.update!(payment_type: 'sponsored')
        notice = "#{user.display_name} payment type set to sponsored."
      else
        user.update!(membership_status: 'sponsored')
        notice = "#{user.display_name} membership status set to sponsored."
      end
    when 'guest'
      if anchor == 'payment-type-unknown'
        user.update!(payment_type: 'guest')
        notice = "#{user.display_name} payment type set to guest."
      else
        user.update!(membership_status: 'guest')
        notice = "#{user.display_name} membership status set to guest."
      end
    when 'cash'
      user.update!(payment_type: 'cash')
      notice = "#{user.display_name} payment type set to cash."
    when 'paypal'
      user.update!(payment_type: 'paypal')
      notice = "#{user.display_name} payment type set to PayPal."
    when 'recharge'
      user.update!(payment_type: 'recharge')
      notice = "#{user.display_name} payment type set to Recharge."
    when 'payment_guest'
      user.update!(payment_type: 'guest')
      notice = "#{user.display_name} payment type set to guest."
    when 'payment_sponsored'
      user.update!(payment_type: 'sponsored')
      notice = "#{user.display_name} payment type set to sponsored."
    else
      redirect_to reports_path, alert: 'Invalid action.'
      return
    end

    if params[:from_view_all] == 'true'
      redirect_to reports_view_all_path(anchor), notice: notice
    else
      redirect_to reports_path(tab: anchor), notice: notice
    end
  end
end
