class MemberSource < ApplicationRecord
  SOURCE_KEYS = %w[authentik member_manager sheet slack].freeze

  validates :key, presence: true, uniqueness: true, inclusion: { in: SOURCE_KEYS }
  validates :name, presence: true

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:display_order, :name) }

  # Find or create source by key
  def self.for(key)
    find_or_create_by!(key: key) do |source|
      source.name = key.titleize.gsub('_', ' ')
      source.display_order = SOURCE_KEYS.index(key) || 99
    end
  end

  # Refresh statistics from actual data
  def refresh_statistics!
    case key
    when 'authentik'
      refresh_authentik_stats!
    when 'member_manager'
      refresh_member_manager_stats!
    when 'sheet'
      refresh_sheet_stats!
    when 'slack'
      refresh_slack_stats!
    end
  end

  # Record a successful sync
  def record_sync!
    update!(last_sync_at: Time.current)
    refresh_statistics!
  end

  # Check if API is configured based on environment variables
  def check_api_configuration!
    configured = case key
                 when 'authentik'
                   ENV['AUTHENTIK_API_TOKEN'].present? && ENV['AUTHENTIK_API_BASE_URL'].present?
                 when 'member_manager'
                   true # Always configured (it's the local database)
                 when 'sheet'
                   ENV['GOOGLE_SHEETS_CREDENTIALS'].present? && ENV['GOOGLE_SHEETS_ID'].present?
                 when 'slack'
                   ENV['SLACK_API_TOKEN'].present?
                 else
                   false
                 end

    update!(api_configured: configured)
  end

  # Seed default sources
  def self.seed_defaults!
    [
      { key: 'authentik', name: 'Authentik', display_order: 1 },
      { key: 'member_manager', name: 'Member Manager', display_order: 2 },
      { key: 'sheet', name: 'Google Sheet', display_order: 3 },
      { key: 'slack', name: 'Slack', display_order: 4 }
    ].each do |attrs|
      source = find_or_initialize_by(key: attrs[:key])
      source.assign_attributes(attrs)
      source.save!
      source.check_api_configuration!
      source.refresh_statistics!
    end
  end

  private

  def refresh_authentik_stats!
    # Use AuthentikUser table for statistics (the source of truth for Authentik data)
    if defined?(AuthentikUser) && ActiveRecord::Base.connection.table_exists?('authentik_users')
      total = AuthentikUser.count
      linked = AuthentikUser.linked.count
      unlinked = AuthentikUser.unlinked.count
      last_sync = AuthentikUser.maximum(:last_synced_at)

      update!(
        entry_count: total,
        linked_count: linked,
        unlinked_count: unlinked,
        last_sync_at: last_sync
      )
    else
      # Table doesn't exist yet - show zeros
      update!(
        entry_count: 0,
        linked_count: 0,
        unlinked_count: 0
      )
    end
  end

  def refresh_member_manager_stats!
    # Member Manager is the User table itself
    total = User.count
    # Consider users "linked" if they have essential data (email or full_name)
    linked = User.where.not(email: [nil, '']).or(User.where.not(full_name: [nil, ''])).count
    unlinked = total - linked

    update!(
      entry_count: total,
      linked_count: linked,
      unlinked_count: unlinked
    )
  end

  def refresh_sheet_stats!
    total = SheetEntry.count
    linked = SheetEntry.where.not(user_id: nil).count
    unlinked = total - linked

    update!(
      entry_count: total,
      linked_count: linked,
      unlinked_count: unlinked
    )
  end

  def refresh_slack_stats!
    total = SlackUser.count
    linked = SlackUser.where.not(user_id: nil).count
    unlinked = total - linked

    update!(
      entry_count: total,
      linked_count: linked,
      unlinked_count: unlinked
    )
  end
end
