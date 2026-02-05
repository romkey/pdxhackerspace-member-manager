class User < ApplicationRecord
  belongs_to :membership_plan, optional: true
  has_one :sheet_entry, dependent: :nullify
  has_one :slack_user, dependent: :nullify
  has_many :paypal_payments, dependent: :nullify
  has_many :recharge_payments, dependent: :nullify
  has_many :journals, dependent: :destroy
  has_many :access_logs, dependent: :nullify
  has_many :rfids, dependent: :destroy
  has_many :trainer_capabilities, dependent: :destroy
  has_many :training_topics, through: :trainer_capabilities
  has_many :user_links, dependent: :destroy
  has_many :trainings_as_trainee, class_name: 'Training', foreign_key: 'trainee_id', dependent: :destroy
  has_many :trainings_as_trainer, class_name: 'Training', foreign_key: 'trainer_id', dependent: :destroy
  has_and_belongs_to_many :application_groups
  has_many :reported_incidents, class_name: 'IncidentReport', foreign_key: 'reporter_id', dependent: :nullify
  has_and_belongs_to_many :incident_reports, join_table: 'incident_report_members'
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

  scope :active, -> { where(active: true) }
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

  def active?
    active
  end

  def username
    self[:username].presence || (authentik_attributes || {})['username'].presence || authentik_id
  end

  def admin?
    is_admin?
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

    # Also check actual payment records
    latest_paypal = paypal_payments.maximum(:transaction_time)
    latest_recharge = recharge_payments.maximum(:processed_at)
    dates << latest_paypal.to_date if latest_paypal.present?
    dates << latest_recharge.to_date if latest_recharge.present?

    dates.compact.max
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

  # Called when a PaypalPayment is linked to this User.
  # Handles payer ID, email syncing, payment type, and membership status.
  # Also links all other PayPal payments with the same payer_id.
  def on_paypal_payment_linked(payment)
    return if payment.blank?

    updates = {}

    # Set paypal_account_id from the payment's payer_id
    if payment.payer_id.present? && paypal_account_id != payment.payer_id
      updates[:paypal_account_id] = payment.payer_id
    end

    # Sync email from payment
    merge_email_from_external_source(payment.payer_email, updates)

    # Set payment_type to 'paypal'
    updates[:payment_type] = 'paypal' if payment_type != 'paypal'

    # Update payment dates and membership status
    apply_payment_updates(payment.transaction_time, updates)

    # Apply all updates at once
    update!(updates) if updates.any?

    # Link all other PayPal payments with the same payer_id to this user
    link_all_paypal_payments_by_payer_id(payment.payer_id)
  end

  # Called when a RechargePayment is linked to this User.
  # Handles customer ID, email syncing, payment type, and membership status.
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

    # Update payment dates and membership status
    apply_payment_updates(payment.processed_at, updates)

    # Apply all updates at once
    update!(updates) if updates.any?

    # Link all other Recharge payments with the same customer_id to this user
    link_all_recharge_payments_by_customer_id(payment.customer_id)
  end

  # Called when a SlackUser is linked to this User.
  # Handles email syncing and Slack profile data.
  def on_slack_user_linked(slack_user)
    return if slack_user.blank?

    updates = {}

    # Sync email from Slack user
    merge_email_from_external_source(slack_user.email, updates)

    # Add slack_id and slack_handle to user (only if not already set)
    updates[:slack_id] = slack_user.slack_id if slack_id.blank?
    updates[:slack_handle] = slack_user.username if slack_handle.blank?

    # Set avatar from Slack profile image_192 if image_original exists (indicating a custom image)
    if slack_user.raw_attributes&.dig('profile', 'image_original').present?
      image_192_url = slack_user.raw_attributes.dig('profile', 'image_192')
      updates[:avatar] = image_192_url if image_192_url.present? && avatar.blank?
    end

    # Apply all updates at once
    update!(updates) if updates.any?
  end

  # Shared method to update user from a payment date.
  # Used by payment linking callbacks and synchronizer reconciliation.
  # Updates last_payment_date and membership status if payment is recent.
  def apply_payment_updates(payment_time, updates = {})
    return updates if payment_time.blank?

    payment_date = payment_time.to_date

    # Update last_payment_date if this payment is more recent
    if last_payment_date.nil? || payment_date > last_payment_date
      updates[:last_payment_date] = payment_date
    end

    # If payment is within the last 32 days, activate user and update status
    if payment_date >= 32.days.ago.to_date
      updates[:active] = true unless active?
      updates[:membership_status] = 'paying' if membership_status != 'paying'
      updates[:dues_status] = 'current' if dues_status != 'current'
    end

    updates
  end

  # Find user by username or ID
  def self.find_by_param(param)
    find_by(username: param) || find(param)
  end

  before_validation :generate_username_if_blank
  before_validation :set_membership_start_date, on: :create
  before_save :ensure_greeting_name_mutual_exclusivity
  before_save :clear_greeting_name_if_do_not_greet
  before_save :auto_fill_greeting_name
  before_save :deactivate_if_deceased
  after_save :update_greeting_name_on_source_change
  after_create_commit :journal_created!
  after_update_commit :journal_updated!
  after_update_commit :sync_to_authentik_if_needed

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
      current_extra_emails = self.extra_emails || []
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
    # Skip if only updated_at changed
    return if saved_changes.except('updated_at').empty?

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
    filtered = saved_changes.except('updated_at', 'created_at', 'last_synced_at')
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

  def deactivate_if_deceased
    return unless membership_status == 'deceased'

    self.active = false
    self.payment_type = 'inactive'
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
    elsif saved_change_to_authentik_id? && use_username_for_greeting?
      update_column(:greeting_name, username) if username.present?
    elsif saved_change_to_username? && use_username_for_greeting?
      update_column(:greeting_name, username) if username.present?
    end
  end

  def ensure_greeting_name_mutual_exclusivity
    if do_not_greet?
      self.use_full_name_for_greeting = false
      self.use_username_for_greeting = false
      return
    end

    if use_full_name_for_greeting? && use_username_for_greeting?
      self.use_username_for_greeting = false
    end

    self.do_not_greet = false if use_full_name_for_greeting? || use_username_for_greeting?
  end

  def sync_to_authentik_if_needed
    return if authentik_id.blank?
    return if Current.skip_authentik_sync

    # Check if any syncable fields changed
    changed_fields = saved_changes.keys & Authentik::UserSync::SYNCABLE_FIELDS
    return if changed_fields.empty?

    # Perform sync asynchronously to avoid blocking
    Authentik::UserSyncJob.perform_later(id, changed_fields)
  end
end
