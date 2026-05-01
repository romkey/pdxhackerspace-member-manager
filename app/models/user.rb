class User < ApplicationRecord
  belongs_to :membership_plan, optional: true # Primary plan
  has_many :user_supplementary_plans, dependent: :destroy
  has_many :supplementary_plans, through: :user_supplementary_plans, source: :membership_plan
  has_one :sheet_entry, dependent: :nullify
  has_one :slack_user, dependent: :nullify
  has_one :authentik_user, dependent: :nullify
  has_many :personal_membership_plans, class_name: 'MembershipPlan', dependent: :destroy
  has_many :paypal_payments, dependent: :nullify
  has_many :recharge_payments, dependent: :nullify
  has_many :cash_payments, dependent: :destroy
  has_many :payment_events, dependent: :destroy
  has_many :journals, dependent: :destroy
  has_many :access_logs, dependent: :nullify
  has_many :rfids, dependent: :destroy
  has_many :trainer_capabilities, dependent: :destroy
  has_many :training_topics, through: :trainer_capabilities
  has_many :training_requests, dependent: :destroy
  has_many :training_requests_responded, class_name: 'TrainingRequest', foreign_key: :responded_by_id,
                                         dependent: :nullify, inverse_of: :responded_by
  has_many :user_links,     dependent: :destroy
  has_many :user_interests, dependent: :destroy
  has_many :interests,      through: :user_interests
  has_many :trainings_as_trainee, class_name: 'Training', foreign_key: 'trainee_id', dependent: :destroy
  has_many :trainings_as_trainer, class_name: 'Training', foreign_key: 'trainer_id', dependent: :destroy
  has_and_belongs_to_many :application_groups
  has_many :queued_mails, foreign_key: 'recipient_id', dependent: :nullify
  has_many :reported_incidents, class_name: 'IncidentReport', foreign_key: 'reporter_id', dependent: :nullify
  has_and_belongs_to_many :incident_reports, join_table: 'incident_report_members'
  has_many :parking_notices, dependent: :nullify
  has_many :membership_applications, -> { newest_first }, dependent: :nullify, inverse_of: :user
  has_many :invitations, dependent: :nullify
  has_many :sent_invitations, class_name: 'Invitation', foreign_key: 'invited_by_id', dependent: :nullify
  has_many :sent_messages, class_name: 'Message', foreign_key: 'sender_id', dependent: :destroy
  has_many :received_messages, class_name: 'Message', foreign_key: 'recipient_id', dependent: :destroy
  validates :authentik_id, uniqueness: true, allow_blank: true
  validates :username, uniqueness: true, allow_blank: true
  validates :email,
            allow_blank: true,
            uniqueness: true,
            format: {
              with: URI::MailTo::EMAIL_REGEXP,
              allow_blank: true
            }
  validates :payment_type, inclusion: { in: %w[unknown sponsored paypal recharge kofi cash inactive] }
  enum :membership_status, {
    paying: 'paying',
    guest: 'guest',
    banned: 'banned',
    deceased: 'deceased',
    sponsored: 'sponsored',
    applicant: 'applicant',
    cancelled: 'cancelled',
    unknown: 'unknown'
  }, default: 'unknown'

  PROFILE_VISIBILITY_OPTIONS = %w[public members private].freeze
  validates :profile_visibility, inclusion: { in: PROFILE_VISIBILITY_OPTIONS }
  validates :dues_status, inclusion: { in: %w[current lapsed inactive unknown] }
  validate :extra_emails_format

  # Submitted with admin user form: if set for guest/sponsored, sets dues_due_at to now + N months
  attr_accessor :sponsored_guest_duration_months

  # Virtual attribute for comma-separated alias editing
  def aliases_text
    (aliases || []).join(', ')
  end

  def aliases_text=(value)
    self.aliases = value.to_s.split(',').map(&:strip).compact_blank.uniq
  end

  # Find a user whose full_name or any alias exactly matches the given name (case-insensitive).
  # No prefix or partial matching — the whole stored name must equal the query string.
  scope :by_name_or_alias, lambda { |name|
    normalized = name.to_s.strip.downcase
    where(
      'LOWER(full_name) = :name OR EXISTS ' \
      '(SELECT 1 FROM unnest(aliases) AS a WHERE LOWER(a) = :name)',
      name: normalized
    )
  }

  scope :active, -> { where(active: true) }
  scope :admin, -> { where(is_admin: true) }
  scope :service_accounts, -> { where(service_account: true) }
  scope :non_service_accounts, -> { where(service_account: false) }
  scope :legacy, -> { where(legacy: true) }
  scope :non_legacy, -> { where(legacy: false) }
  scope :is_sponsored, -> { where(is_sponsored: true) }
  scope :authentik_dirty, -> { where(authentik_dirty: true) }
  scope :with_attribute, ->(key, value) { where('authentik_attributes ->> ? = ?', key.to_s, value.to_s) }
  scope :ordered_by_display_name, lambda {
    order(
      Arel.sql("LOWER(COALESCE(NULLIF(full_name, ''), NULLIF(email, ''), authentik_id)) ASC"),
      :email,
      :authentik_id
    )
  }

  def display_name
    full_name.presence || email.presence || authentik_id
  end

  # Add a name as an alias if it differs from full_name and isn't already present.
  # Returns true if the alias was added, false otherwise.
  def add_alias(name)
    return false if name.blank?

    normalized = name.to_s.strip
    return false if normalized.blank?
    return false if full_name.present? && full_name.strip.downcase == normalized.downcase
    return false if (aliases || []).any? { |a| a.strip.downcase == normalized.downcase }

    self.aliases = (aliases || []) + [normalized]
    true
  end

  # Add alias and save immediately.
  def add_alias!(name)
    add_alias(name) && save!
  end

  def active?
    active
  end

  def username
    self[:username].presence || (authentik_attributes || {})['username'].presence || authentik_id
  end

  def admin?
    is_admin?
  end

  def trained_in_executive_director_topic?
    topic = TrainingTopic.where('LOWER(name) = ?', MembershipApplication::EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME.downcase).first
    return false if topic.nil?

    Training.exists?(trainee: self, training_topic: topic)
  end

  # Approve/reject membership applications: admins with Executive Director training when that topic exists.
  def can_finalize_membership_application?
    return false unless is_admin?

    topic = TrainingTopic.where('LOWER(name) = ?', MembershipApplication::EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME.downcase).first
    return true if topic.nil?

    trained_in_executive_director_topic?
  end

  # Get training topics with links that the user is trained in
  # Returns topics ordered alphabetically by name, only those with at least one link
  def training_topics_with_links
    trained_topic_ids = trainings_as_trainee.pluck(:training_topic_id).uniq
    return [] if trained_topic_ids.empty?

    TrainingTopic.where(id: trained_topic_ids)
                 .joins(:links)
                 .distinct
                 .includes(:links)
                 .order(:name)
  end

  # Get documents available to this user based on their training or show_on_all_profiles flag
  # Returns deduplicated list ordered alphabetically by title
  def available_documents
    # Get all training topic IDs the user is trained in
    trained_topic_ids = trainings_as_trainee.pluck(:training_topic_id).uniq

    # Get documents shown to all profiles OR associated with trained topics
    if trained_topic_ids.empty?
      Document.where(show_on_all_profiles: true).ordered
    else
      Document.left_joins(:document_training_topics)
              .where(
                'documents.show_on_all_profiles = ? OR document_training_topics.training_topic_id IN (?)',
                true,
                trained_topic_ids
              )
              .distinct
              .ordered
    end
  end

  # Get the most recent payment date across all payment sources
  def most_recent_payment_date
    dates = []
    dates << last_payment_date if last_payment_date.present?
    dates << recharge_most_recent_payment_date.to_date if recharge_most_recent_payment_date.present?

    latest_paypal = paypal_payments.maximum(:transaction_time)
    latest_recharge = recharge_payments.maximum(:processed_at)
    latest_cash = cash_payments.maximum(:paid_on)
    dates << latest_paypal.to_date if latest_paypal.present?
    dates << latest_recharge.to_date if latest_recharge.present?
    dates << latest_cash if latest_cash.present?

    dates.compact.max
  end

  # Next billing-cycle boundary (paying) or end of limited guest/sponsored access, persisted on `dues_due_at`.
  def next_payment_date
    dues_due_at&.to_date
  end

  # When the next payment is due after a payment on anchor_date, given the plan's billing frequency.
  def self.dues_due_at_from_payment_cycle(anchor_date, plan)
    return nil if anchor_date.blank? || plan.blank?

    d = case plan.billing_frequency
        when 'monthly' then anchor_date.to_date + 1.month
        when 'yearly' then anchor_date.to_date + 1.year
        when 'one-time' then nil
        end
    d&.in_time_zone&.beginning_of_day
  end

  def limited_guest_or_sponsored_access_expired?
    dues_due_at.present? && dues_due_at < Time.current
  end

  PAYMENT_GRACE_DAYS = 2

  # How long after a payment the user is still considered current.
  # Based on the membership plan's billing cycle plus a small grace window.
  # Returns nil for one-time plans (payment never expires).
  # Falls back to 32 days when no plan is assigned.
  def payment_currency_window
    cycle = membership_plan&.billing_cycle_duration
    return cycle + PAYMENT_GRACE_DAYS.days if cycle

    membership_plan&.billing_frequency == 'one-time' ? nil : 32.days
  end

  # Check if user is within the reactivation grace period
  def within_reactivation_grace_period?
    return false unless dues_status == 'lapsed'

    last_payment = most_recent_payment_date
    return false if last_payment.blank?

    grace_months = MembershipSetting.reactivation_grace_period_months
    cutoff_date = grace_months.months.ago.to_date
    last_payment >= cutoff_date
  end

  # Calculate when the reactivation grace period expires
  def reactivation_expires_on
    return nil unless dues_status == 'lapsed'

    last_payment = most_recent_payment_date
    return nil if last_payment.blank?

    grace_months = MembershipSetting.reactivation_grace_period_months
    last_payment + grace_months.months
  end

  # Check if user is lapsed and past the grace period (needs re-orientation)
  def past_reactivation_grace_period?
    return false unless dues_status == 'lapsed'

    last_payment = most_recent_payment_date
    # If no payment history, they're past the grace period
    return true if last_payment.blank?

    grace_months = MembershipSetting.reactivation_grace_period_months
    cutoff_date = grace_months.months.ago.to_date
    last_payment < cutoff_date
  end

  # Use username in URLs instead of ID
  def to_param
    username.presence || id.to_s
  end

  def generate_login_token!
    expiry = if admin?
               MembershipSetting.admin_login_link_expiry_minutes.minutes.from_now
             else
               MembershipSetting.login_link_expiry_hours.hours.from_now
             end
    update!(
      login_token: SecureRandom.alphanumeric(64),
      login_token_expires_at: expiry
    )
  end

  def clear_login_token!
    update!(login_token: nil, login_token_expires_at: nil)
  end

  def login_token_expired?
    login_token_expires_at.present? && login_token_expires_at <= Time.current
  end

  def login_token_active?
    login_token.present? && !login_token_expired?
  end

  # Called when a PaypalPayment is linked to this User.
  # Handles payer ID, email syncing, payment type, membership status, and plan matching.
  # Also links all other PayPal payments with the same payer_id.
  def on_paypal_payment_linked(payment)
    return if payment.blank?

    updates = {}

    # Set paypal_account_id from the payment's payer_id
    updates[:paypal_account_id] = payment.payer_id if payment.payer_id.present? && paypal_account_id != payment.payer_id

    # Sync email from payment
    merge_email_from_external_source(payment.payer_email, updates)

    # Set payment_type to 'paypal'
    updates[:payment_type] = 'paypal' if payment_type != 'paypal'

    # Update payment dates, membership status, and try to match plan
    apply_payment_updates({ time: payment.transaction_time, amount: payment.amount }, updates)

    # Apply all updates at once
    update!(updates) if updates.any?

    # Link all other PayPal payments with the same payer_id to this user
    link_all_paypal_payments_by_payer_id(payment.payer_id)

    # Create payment events for all linked PayPal payments
    ensure_paypal_payment_events(payment.payer_id)
  end

  # Called when a RechargePayment is linked to this User.
  # Handles customer ID, email syncing, payment type, membership status, and plan matching.
  # Also links all other Recharge payments with the same customer_id.
  def on_recharge_payment_linked(payment)
    return if payment.blank?

    updates = {}

    # Set recharge_customer_id from the payment's customer_id
    if payment.customer_id.present? && recharge_customer_id != payment.customer_id.to_s
      updates[:recharge_customer_id] = payment.customer_id.to_s
    end

    # Sync email from payment
    merge_email_from_external_source(payment.customer_email, updates)

    # Set payment_type to 'recharge'
    updates[:payment_type] = 'recharge' if payment_type != 'recharge'

    # Update recharge_most_recent_payment_date
    if payment.processed_at.present?
      payment_date = payment.processed_at.to_date
      if recharge_most_recent_payment_date.nil? || payment_date > recharge_most_recent_payment_date.to_date
        updates[:recharge_most_recent_payment_date] = payment.processed_at
      end
    end

    # Update payment dates, membership status, and try to match plan
    apply_payment_updates({ time: payment.processed_at, amount: payment.amount }, updates)

    # Apply all updates at once
    update!(updates) if updates.any?

    # Link all other Recharge payments with the same customer_id to this user
    link_all_recharge_payments_by_customer_id(payment.customer_id)

    # Create payment events for all linked Recharge payments
    ensure_recharge_payment_events(payment.customer_id)
  end

  # Shared method to update user from a payment.
  # Used by payment linking callbacks and synchronizer reconciliation.
  # Updates last_payment_date, membership status, and membership plan if needed.
  # Can accept either a time or a hash with :time and :amount.
  def apply_payment_updates(payment_time_or_options, updates = {})
    return updates if payment_time_or_options.blank?

    # Support both simple time and options hash
    if payment_time_or_options.is_a?(Hash)
      payment_time = payment_time_or_options[:time]
      payment_amount = payment_time_or_options[:amount]
    else
      payment_time = payment_time_or_options
      payment_amount = nil
    end

    return updates if payment_time.blank?

    payment_date = payment_time.to_date

    # Update last_payment_date if this payment is more recent
    updates[:last_payment_date] = payment_date if last_payment_date.nil? || payment_date > last_payment_date

    # If payment is within the billing cycle window, update membership and dues status.
    # (active will be computed automatically by the before_save callback)
    window = payment_currency_window
    payment_is_current = window.nil? || payment_date >= window.ago.to_date
    if payment_is_current
      # Don't override deliberate statuses — these are set by admin actions,
      # webhooks, or subscription sync and should not be reverted by the
      # presence of a historical payment.
      if !membership_status.in?(%w[cancelled banned deceased sponsored]) && (membership_status != 'paying')
        updates[:membership_status] = 'paying'
      end
      updates[:dues_status] = 'current' if dues_status != 'current'
      updates[:membership_ended_date] = nil if membership_ended_date.present?
    end

    maybe_match_plan_from_payment_amount!(updates, payment_amount)

    merge_dues_due_at_after_payment!(updates, payment_date)

    updates
  end

  def merge_dues_due_at_after_payment!(updates, payment_date)
    status = updates[:membership_status] || membership_status
    return if status.in?(%w[guest sponsored banned deceased])

    anchor = [last_payment_date, payment_date, updates[:last_payment_date]].compact.max
    plan_id = updates[:membership_plan_id] || membership_plan_id
    plan = MembershipPlan.find_by(id: plan_id)
    updates[:dues_due_at] = User.dues_due_at_from_payment_cycle(anchor, plan)
  end

  def maybe_match_plan_from_payment_amount!(updates, payment_amount)
    return unless membership_plan_id.blank? && payment_amount.present? && payment_amount.positive?

    matched_plan = find_matching_membership_plan(payment_amount)
    updates[:membership_plan_id] = matched_plan.id if matched_plan
  end

  # Find a membership plan that matches the given payment amount
  # Only matches primary plans for the primary plan slot
  def find_matching_membership_plan(amount)
    return nil if amount.blank? || amount <= 0

    plans = MembershipPlan.primary

    # Try exact match first
    exact_match = plans.find { |p| p.cost == amount }
    return exact_match if exact_match

    # Try matching within a small tolerance (for rounding differences)
    tolerance = 0.50
    close_match = plans.find { |p| (p.cost - amount).abs <= tolerance }
    return close_match if close_match

    nil
  end

  # Get all membership plans (primary + supplementary)
  def all_membership_plans
    plans = []
    plans << membership_plan if membership_plan.present?
    plans + supplementary_plans.order(:name).to_a
  end

  # Add a supplementary plan to this user (idempotent)
  def add_supplementary_plan(plan)
    return false unless plan&.supplementary?
    return true if supplementary_plans.include?(plan)

    user_supplementary_plans.create(membership_plan: plan)
    true
  end

  # Remove a supplementary plan from this user
  def remove_supplementary_plan(plan)
    user_supplementary_plans.where(membership_plan: plan).destroy_all
  end

  # Check if user has a specific plan (primary or supplementary)
  def has_plan?(plan)
    membership_plan_id == plan.id || supplementary_plans.exists?(plan.id)
  end

  # Find user by username or ID
  def self.find_by_param(param)
    find_by(username: param) || find(param)
  end

  # Returns which greeting option is currently active: 'full_name', 'username', 'custom', or 'do_not_greet'
  def greeting_option
    return 'full_name' if use_full_name_for_greeting?
    return 'username' if use_username_for_greeting?
    return 'do_not_greet' if do_not_greet?

    'custom'
  end

  before_validation :generate_username_if_blank
  before_validation :set_membership_start_date, on: :create
  before_validation :apply_sponsored_guest_duration_months
  before_save :ensure_greeting_name_mutual_exclusivity
  before_save :clear_greeting_name_if_do_not_greet
  before_save :auto_fill_greeting_name
  before_save :compute_active_status
  before_save :clear_legacy_if_meaningful_data
  before_save :mark_authentik_dirty_if_needed
  after_save :update_greeting_name_on_source_change
  after_create_commit :journal_created!
  after_create_commit :provision_to_authentik
  after_create_commit :sync_application_group_memberships_on_create
  after_update_commit :journal_updated!
  after_update_commit :sync_authentik_user_if_needed
  after_update_commit :sync_application_group_memberships_on_update
  after_update_commit :queue_lapsed_email_if_needed

  private

  # Merge an email from an external source (Slack, PayPal, Recharge, etc.)
  # If user has no email, sets it. If different, adds to extra_emails.
  def merge_email_from_external_source(external_email, updates = {})
    return updates if external_email.blank?

    external_email_normalized = external_email.to_s.strip.downcase

    if email.blank?
      # User has no email, set it from external source
      updates[:email] = external_email
    elsif email.downcase != external_email_normalized
      # User has different primary email, add to extra_emails if not already there
      current_extra_emails = extra_emails || []
      unless current_extra_emails.map(&:downcase).include?(external_email_normalized)
        updates[:extra_emails] = current_extra_emails + [external_email]
      end
    end

    updates
  end

  # Link all Recharge payments with the given customer_id to this user.
  # Uses update_all to avoid triggering callbacks (which would cause infinite recursion).
  def link_all_recharge_payments_by_customer_id(customer_id)
    return if customer_id.blank?

    # Find all unlinked payments with this customer_id and link them
    # Use update_all to avoid triggering the after_save callback again
    RechargePayment.where(customer_id: customer_id.to_s, user_id: nil)
                   .update_all(user_id: id)
  end

  # Link all PayPal payments with the given payer_id to this user.
  # Uses update_all to avoid triggering callbacks (which would cause infinite recursion).
  def link_all_paypal_payments_by_payer_id(payer_id)
    return if payer_id.blank?

    # Find all unlinked payments with this payer_id and link them
    # Use update_all to avoid triggering the after_save callback again
    PaypalPayment.where(payer_id: payer_id.to_s, user_id: nil)
                 .update_all(user_id: id)
  end

  # Find or create PaymentEvent records for all PayPal payments with the given payer_id.
  # Updates existing orphaned events (user_id nil) and creates missing ones.
  def ensure_paypal_payment_events(payer_id)
    return if payer_id.blank?

    PaypalPayment.where(payer_id: payer_id.to_s, user_id: id).find_each do |pp|
      pe = PaymentEvent.find_or_create_by!(source: 'paypal', external_id: pp.paypal_id,
                                           event_type: 'payment') do |event|
        event.user = self
        event.amount = pp.amount
        event.currency = pp.currency || 'USD'
        event.occurred_at = pp.transaction_time || pp.created_at
        event.details = "PayPal payment from #{pp.payer_name || pp.payer_email}"
        event.paypal_payment = pp
      end
      pe.update!(user: self) if pe.user_id != id
    end
  end

  # Find or create PaymentEvent records for all Recharge payments with the given customer_id.
  # Updates existing orphaned events (user_id nil) and creates missing ones.
  def ensure_recharge_payment_events(customer_id)
    return if customer_id.blank?

    RechargePayment.where(customer_id: customer_id.to_s, user_id: id).find_each do |rp|
      pe = PaymentEvent.find_or_create_by!(
        source: 'recharge', external_id: rp.recharge_id, event_type: 'payment'
      ) do |event|
        event.user = self
        event.amount = rp.amount
        event.currency = rp.currency || 'USD'
        event.occurred_at = rp.processed_at || rp.created_at
        event.details = "Recharge payment from #{rp.customer_name || rp.customer_email}"
        event.recharge_payment = rp
      end
      pe.update!(user: self) if pe.user_id != id
    end
  end

  def generate_username_if_blank
    return if self[:username].present?
    return if full_name.blank?

    # Generate base username from full name: lowercase, remove special chars and spaces
    base_username = full_name.downcase
                             .gsub(/[^a-z0-9\s]/, '') # Remove special characters
                             .gsub(/\s+/, '')         # Remove all whitespace
                             .truncate(50, omission: '') # Limit length

    return if base_username.blank?

    # Find a unique username
    candidate = base_username
    counter = 1

    while User.where(username: candidate).where.not(id: id).exists?
      candidate = "#{base_username}#{counter}"
      counter += 1
    end

    self.username = candidate
  end

  def set_membership_start_date
    self.membership_start_date ||= Date.current
  end

  def journal_created!
    changes = saved_changes_to_json_hash
    # Ensure changes_json is never empty
    changes = { '_system_note' => { 'from' => nil, 'to' => 'User record created' } } if changes.empty?

    Journal.create!(
      user: self,
      actor_user: Current.user, # nil when done by system (login, sync, etc.)
      action: 'created',
      changes_json: changes,
      changed_at: Time.current
    )
  end

  def journal_updated!
    # Skip if only noisy/internal fields changed
    return if saved_changes.except('updated_at', 'authentik_dirty').empty?

    # Skip journal when only change is marking as legacy (legacy false -> true).
    # We DO want a journal entry when un-marking legacy (true -> false).
    if saved_changes.key?('legacy')
      _, to = saved_changes['legacy']
      other_changes = saved_changes.except('updated_at', 'authentik_dirty', 'legacy')
      return if to == true && other_changes.empty?
    end

    changes = saved_changes_to_json_hash
    # Ensure changes_json is never empty
    changes = { '_system_note' => { 'from' => nil, 'to' => 'User record updated' } } if changes.empty?

    Journal.create!(
      user: self,
      actor_user: Current.user, # nil when done by system (login, sync, etc.)
      action: 'updated',
      changes_json: changes,
      changed_at: Time.current
    )
  end

  def saved_changes_to_json_hash
    # Convert saved_changes to a { attr => { from: old, to: new } } structure,
    # and filter out noisy attributes.
    filtered = saved_changes.except('updated_at', 'created_at', 'last_synced_at', 'authentik_dirty')
    filtered.to_h do |attr, (from, to)|
      [attr, { 'from' => from, 'to' => to }]
    end
  end

  def extra_emails_format
    return if extra_emails.blank?

    extra_emails.each do |email|
      errors.add(:extra_emails, "contains invalid email: #{email}") unless email.match?(URI::MailTo::EMAIL_REGEXP)
    end
  end

  # For non-service accounts, compute `active` from membership_status and dues_status.
  # Service accounts manage their own active flag manually.
  # Limited guest/sponsored access expires when `dues_due_at` is in the past.
  def compute_active_status
    return if service_account?

    if emergency_active_override?
      self.active = true
      return
    end

    if is_sponsored?
      self.active = !limited_guest_or_sponsored_access_expired?
      return
    end

    self.active = case membership_status
                  when 'sponsored', 'guest'
                    !limited_guest_or_sponsored_access_expired?
                  when 'paying', 'cancelled', 'unknown'
                    dues_status == 'current'
                  else
                    false
                  end

    self.payment_type = 'inactive' if membership_status == 'deceased'
  end

  def apply_sponsored_guest_duration_months
    return unless membership_status.in?(%w[guest sponsored])
    return if sponsored_guest_duration_months.blank?

    months = sponsored_guest_duration_months.to_i
    self.dues_due_at = months.positive? ? Time.current + months.months : nil
  end

  # Auto-remove legacy flag when the account *gets* meaningful payment/membership data.
  # Only triggers when the relevant fields are actually changing in this save,
  # not when legacy itself is being set on a record that already has some data.
  # This triggers a journal entry (un-marking legacy is journaled).
  def clear_legacy_if_meaningful_data
    return unless legacy?

    # Only auto-clear if one of the meaningful data fields is changing in this save
    meaningful_fields = %w[membership_plan_id dues_status last_payment_date recharge_most_recent_payment_date
                           membership_status is_sponsored dues_due_at]
    return unless changes.keys.intersect?(meaningful_fields)

    has_plan = membership_plan_id.present?
    has_non_unknown_dues = dues_status.present? && dues_status != 'unknown'
    has_payment_date = last_payment_date.present? || recharge_most_recent_payment_date.present?
    has_paying_status = membership_status.in?(%w[paying sponsored])

    return unless has_plan || has_non_unknown_dues || has_payment_date || has_paying_status || is_sponsored?

    self.legacy = false
  end

  def clear_greeting_name_if_do_not_greet
    self.greeting_name = nil if do_not_greet?
  end

  def auto_fill_greeting_name
    return if do_not_greet?

    if use_full_name_for_greeting?
      self.greeting_name = full_name if full_name.present?
    elsif use_username_for_greeting?
      self.greeting_name = username if username.present?
    end
  end

  def update_greeting_name_on_source_change
    # Update greeting_name if the source field changed and the corresponding boolean is set
    return if do_not_greet?

    if saved_change_to_full_name? && use_full_name_for_greeting?
      update_column(:greeting_name, full_name) if full_name.present?
    elsif (saved_change_to_authentik_id? || saved_change_to_username?) && use_username_for_greeting?
      update_column(:greeting_name, username) if username.present?
    end
  end

  def ensure_greeting_name_mutual_exclusivity
    if do_not_greet?
      self.use_full_name_for_greeting = false
      self.use_username_for_greeting = false
      return
    end

    self.use_username_for_greeting = false if use_full_name_for_greeting? && use_username_for_greeting?

    self.do_not_greet = false if use_full_name_for_greeting? || use_username_for_greeting?
  end

  # Fields that correspond to Authentik user attributes
  AUTHENTIK_SYNCABLE_FIELDS = %w[email full_name username active].freeze
  private_constant :AUTHENTIK_SYNCABLE_FIELDS

  # Mark user as needing sync to Authentik when syncable fields change
  def mark_authentik_dirty_if_needed
    return if Current.skip_authentik_sync

    changed = changes.keys & AUTHENTIK_SYNCABLE_FIELDS
    return if changed.empty?

    self.authentik_dirty = true
  end

  def provision_to_authentik
    return if Current.skip_authentik_sync

    Authentik::ProvisionUserJob.perform_later(id)
  end

  def sync_authentik_user_if_needed
    return if Current.skip_authentik_sync

    changed_fields = saved_changes.keys & Authentik::UserSync::SYNCABLE_FIELDS
    return if changed_fields.empty?

    if authentik_id.present?
      Authentik::UserSyncJob.perform_later(id, changed_fields)
    else
      Authentik::ProvisionUserJob.perform_later(id)
    end
  end

  def sync_application_group_memberships_on_create
    return if Current.skip_authentik_sync

    sources = %w[all_members]
    sources << 'active_members' if active?
    sources << 'unbanned_members' unless banned?
    sources << 'admin_members' if is_admin?

    Authentik::ApplicationGroupMembershipSyncJob.perform_later(sources)
  end

  def sync_application_group_memberships_on_update
    return if Current.skip_authentik_sync

    sources = []

    sources << 'active_members' if saved_change_to_active?

    if saved_change_to_membership_status?
      old_status, new_status = saved_change_to_membership_status
      if old_status == 'banned' || new_status == 'banned'
        sources << 'unbanned_members'
        sources << 'active_members' unless sources.include?('active_members')
      end
    end

    sources << 'admin_members' if saved_change_to_is_admin?

    if saved_change_to_authentik_id? && authentik_id.present?
      sources << 'all_members'
      sources << 'active_members' if active?
      sources << 'unbanned_members' unless banned?
      sources << 'admin_members' if is_admin?
    end

    return if sources.empty?

    sources << 'all_members'
    Authentik::ApplicationGroupMembershipSyncJob.perform_later(sources.uniq)
  end

  def queue_lapsed_email_if_needed
    return unless saved_change_to_dues_status?
    return unless dues_status == 'lapsed'
    return if email.blank?

    QueuedMail.enqueue(:membership_lapsed, self, reason: "Membership dues lapsed for #{display_name}")
  end
end
