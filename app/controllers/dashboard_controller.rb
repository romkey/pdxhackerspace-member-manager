class DashboardController < AdminController
  def index
    @user_count = User.non_legacy.count
    @active_user_count = User.active.count
    @last_synced_at = User.maximum(:last_synced_at)
    @sheet_entry_count = SheetEntry.count
    @slack_user_count = SlackUser.count
    @paypal_payment_count = PaypalPayment.count
    @recharge_payment_count = RechargePayment.count

    # Count members on manual plans
    manual_plan_ids = MembershipPlan.manual.pluck(:id)
    @manual_payment_member_count = if manual_plan_ids.any?
                                     User.where(membership_plan_id: manual_plan_ids).count +
                                       UserSupplementaryPlan
                                       .where(membership_plan_id: manual_plan_ids)
                                       .select(:user_id).distinct.count
                                   else
                                     0
                                   end

    @queued_mail_count = QueuedMail.pending.count

    prepare_attention_items

    # Highlighted journal entries from the last 2 weeks
    @recent_highlights = Journal.highlighted
                                .includes(:user, :actor_user)
                                .where(changed_at: 2.weeks.ago..)
                                .order(changed_at: :desc)
                                .limit(50)
  end

  private

  def prepare_attention_items
    # Urgent: Access controller issues
    enabled_controllers = AccessController.enabled
    @ac_offline_count = enabled_controllers.where(ping_status: 'failed').count
    @ac_sync_failed_count = enabled_controllers.where(sync_status: 'failed').count
    @ac_backup_failed_count = enabled_controllers.where(backup_status: 'failed').count
    @ac_issue_count = @ac_offline_count + @ac_sync_failed_count + @ac_backup_failed_count

    # Urgent: Unlinked Recharge payments
    @unlinked_recharge_count = RechargePayment.where(user_id: nil, dont_link: false).count

    # Urgent: Payment processor API sync failures (PayPal / Recharge jobs)
    @payment_processors_sync_unhealthy = PaymentProcessor.enabled
                                                         .where(sync_status: %w[degraded failing])
                                                         .order(:name)

    # Urgent: Authentik API not configured (login and/or member sync enabled)
    @authentik_member_source = MemberSource.find_by(key: 'authentik')
    @authentik_api_urgent = !AuthentikConfig.api_ready? &&
                            (AuthentikConfig.enabled_for_login? || @authentik_member_source&.enabled?)

    # Urgent: Authentik pull/push sync failures
    @authentik_sync_issue = @authentik_member_source if @authentik_member_source&.enabled? &&
                                                        @authentik_member_source.sync_status.in?(%w[degraded failing])

    # Important: Open and draft incident reports
    @open_incident_count = IncidentReport.where(status: 'in_progress').count
    @draft_incident_count = IncidentReport.where(status: 'draft').count
    @active_incident_count = @open_incident_count + @draft_incident_count

    # Important: Email templates needing review
    @templates_needing_review_count = EmailTemplate.needs_review.count

    # Important: Member-suggested interests needing review
    @interests_needing_review_count = Interest.needs_review.count

    # Important: Pending membership applications
    @pending_applications_count = MembershipApplication.pending.count
    @submitted_applications_count = MembershipApplication.submitted_apps.count
    @under_review_applications_count = MembershipApplication.under_review.count

    # Important: Parking notices
    @active_parking_permit_count = ParkingNotice.permits.active_notices.count
    @active_parking_ticket_count = ParkingNotice.tickets.active_notices.count
    @active_parking_count = @active_parking_permit_count + @active_parking_ticket_count
    @expired_parking_permit_count = ParkingNotice.permits.expired_notices.count
    @expired_parking_ticket_count = ParkingNotice.tickets.expired_notices.count
    @expired_parking_count = @expired_parking_permit_count + @expired_parking_ticket_count

    # Housekeeping: Lapsed members with access after lapse
    lapsed_users = User.where(dues_status: 'lapsed')
                       .where.not(membership_status: %w[banned deceased])
                       .non_service_accounts
                       .non_legacy
                       .includes(:access_logs)
    @lapsed_with_access_count = 0
    lapsed_users.find_each do |user|
      last_payment = user.most_recent_payment_date
      next if last_payment.blank?

      @lapsed_with_access_count += 1 if user.access_logs.exists?(['logged_at > ?', last_payment.end_of_day])
    end

    # Housekeeping: Legacy members with recent access (last year)
    @legacy_recent_access_count = User.where(legacy: true)
                                      .non_service_accounts
                                      .joins(:access_logs)
                                      .where(access_logs: { logged_at: 1.year.ago.. })
                                      .distinct
                                      .count

    # Housekeeping: Lapsed members with Slack accounts
    @lapsed_with_slack_count = User.where(dues_status: 'lapsed')
                                   .where.not(membership_status: %w[banned deceased])
                                   .non_service_accounts
                                   .non_legacy
                                   .joins(:slack_user)
                                   .count

    # Housekeeping: Legacy members with Slack accounts
    @legacy_with_slack_count = User.where(legacy: true)
                                   .non_service_accounts
                                   .joins(:slack_user)
                                   .count

    # Housekeeping: Lapsed members still active on Slack
    @lapsed_active_slack_count = User.where(dues_status: 'lapsed')
                                     .where.not(membership_status: %w[banned deceased])
                                     .non_service_accounts
                                     .non_legacy
                                     .joins(:slack_user)
                                     .where.not(slack_users: { last_active_at: nil })
                                     .where(
                                       'slack_users.last_active_at > ' \
                                       'COALESCE(users.membership_ended_date, users.created_at)'
                                     )
                                     .count

    # Housekeeping: Legacy members still active on Slack
    @legacy_active_slack_count = User.where(legacy: true)
                                     .non_service_accounts
                                     .joins(:slack_user)
                                     .where.not(slack_users: { last_active_at: nil })
                                     .count

    # Housekeeping: Slack users inactive for over a year
    @slack_inactive_count = SlackUser.active
                                     .where('last_active_at < ? OR last_active_at IS NULL', 1.year.ago)
                                     .count

    # Housekeeping: Active members with no email
    @active_no_email_count = User.where(active: true)
                                 .where(email: [nil, ''])
                                 .count

    @ai_ollama_profiles = AiOllamaProfile.ordered.to_a
    @ai_ollama_urgent = @ai_ollama_profiles.any?(&:urgent_health_issue?)

    @emergency_active_override_count = User.non_service_accounts.where(emergency_active_override: true).count

    @dashboard_attention_items = build_dashboard_attention_items
  end

  def build_dashboard_attention_items
    [
      { tier: :urgent, id: :ac_issues, ok: @ac_issue_count.zero? },
      { tier: :urgent, id: :payment_processors, ok: @payment_processors_sync_unhealthy.empty? },
      { tier: :urgent, id: :authentik, ok: authentik_dashboard_ok? },
      { tier: :urgent, id: :ai_ollama, ok: !@ai_ollama_urgent },
      { tier: :important, id: :membership_applications, ok: @pending_applications_count.zero? },
      { tier: :important, id: :unlinked_recharge, ok: @unlinked_recharge_count.zero? },
      { tier: :important, id: :mail_queue, ok: @queued_mail_count.zero? },
      { tier: :important, id: :incidents, ok: @active_incident_count.zero? },
      { tier: :important, id: :email_templates, ok: @templates_needing_review_count.zero? },
      { tier: :important, id: :interests, ok: @interests_needing_review_count.zero? },
      { tier: :important, id: :emergency_active_overrides, ok: @emergency_active_override_count.zero? },
      { tier: :important, id: :parking_active, ok: @active_parking_count.zero? },
      { tier: :important, id: :parking_expired, ok: @expired_parking_count.zero? },
      { tier: :important, id: :manual_payments_due, ok: true },
      { tier: :housekeeping, id: :lapsed_with_access, ok: @lapsed_with_access_count.zero? },
      { tier: :housekeeping, id: :legacy_recent_access, ok: @legacy_recent_access_count.zero? },
      { tier: :housekeeping, id: :lapsed_with_slack, ok: @lapsed_with_slack_count.zero? },
      { tier: :housekeeping, id: :legacy_with_slack, ok: @legacy_with_slack_count.zero? },
      { tier: :housekeeping, id: :lapsed_active_slack, ok: @lapsed_active_slack_count.zero? },
      { tier: :housekeeping, id: :legacy_active_slack, ok: @legacy_active_slack_count.zero? },
      { tier: :housekeeping, id: :slack_inactive, ok: @slack_inactive_count.zero? },
      { tier: :housekeeping, id: :active_no_email, ok: @active_no_email_count.zero? }
    ].freeze
  end

  def authentik_dashboard_ok?
    return false if @authentik_api_urgent
    return true if @authentik_member_source.nil? || !@authentik_member_source.enabled?
    return false if @authentik_sync_issue

    true
  end
end
