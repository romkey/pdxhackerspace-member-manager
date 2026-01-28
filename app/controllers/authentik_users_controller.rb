# SPDX-FileCopyrightText: 2026 John Romkey
#
# SPDX-License-Identifier: CC0-1.0

class AuthentikUsersController < AdminController
  before_action :set_authentik_user, only: [:show, :link_user, :accept_changes, :push_to_authentik]

  def index
    @authentik_users = AuthentikUser.includes(:user).order(updated_at: :desc)

    # Counts for all records
    @total_count = AuthentikUser.count
    @linked_count = AuthentikUser.linked.count
    @unlinked_count = AuthentikUser.unlinked.count
    @active_count = AuthentikUser.active.count
    @inactive_count = AuthentikUser.inactive.count
    @discrepancy_count = AuthentikUser.with_discrepancies.count

    # Filter options
    case params[:filter]
    when 'unlinked'
      @authentik_users = @authentik_users.unlinked
    when 'linked'
      @authentik_users = @authentik_users.linked
    when 'discrepancies'
      @authentik_users = @authentik_users.with_discrepancies
    when 'active'
      @authentik_users = @authentik_users.active
    when 'inactive'
      @authentik_users = @authentik_users.inactive
    end
  end

  def show
    @all_users = User.order(:full_name, :email) if @authentik_user.user.nil?

    # Navigation
    ids = AuthentikUser.order(updated_at: :desc).pluck(:id)
    current_index = ids.index(@authentik_user.id)
    @previous_authentik_user = current_index&.positive? ? AuthentikUser.find(ids[current_index - 1]) : nil
    @next_authentik_user = current_index && current_index < ids.length - 1 ? AuthentikUser.find(ids[current_index + 1]) : nil
  end

  def sync
    Authentik::GroupSyncJob.perform_later
    redirect_to authentik_users_path, notice: 'Authentik sync started.'
  end

  def link_user
    user = User.find(params[:user_id])
    @authentik_user.update!(user: user)

    # Also update the user's authentik_id if not set
    user.update!(authentik_id: @authentik_user.authentik_id) if user.authentik_id.blank?

    # Update MemberSource statistics
    MemberSource.for('authentik').refresh_statistics!

    redirect_to authentik_user_path(@authentik_user), notice: "Linked to #{user.display_name}."
  end

  def accept_changes
    unless @authentik_user.user
      redirect_to @authentik_user, alert: 'No linked user to update.'
      return
    end

    updates = {}
    @authentik_user.discrepancies.each do |discrepancy|
      field = discrepancy[:field]
      updates[field] = @authentik_user.send(field)
    end

    if updates.any?
      @authentik_user.user.update!(updates)

      JournalEntry.create!(
        user: @authentik_user.user,
        action: 'authentik_sync',
        description: "Accepted Authentik values for: #{updates.keys.join(', ')}",
        metadata: { updates: updates, authentik_user_id: @authentik_user.id }
      )

      redirect_to @authentik_user, notice: "Updated user with Authentik values: #{updates.keys.join(', ')}."
    else
      redirect_to @authentik_user, notice: 'No discrepancies to resolve.'
    end
  end

  def push_to_authentik
    unless @authentik_user.user
      redirect_to @authentik_user, alert: 'No linked user to push.'
      return
    end

    # TODO: Implement Authentik API update
    # This would use the Authentik::Client to update the user in Authentik
    # Authentik::Client.new.update_user(@authentik_user.authentik_id, {
    #   email: @authentik_user.user.email,
    #   name: @authentik_user.user.full_name,
    #   username: @authentik_user.user.username
    # })

    redirect_to @authentik_user, alert: 'Push to Authentik is not yet implemented. This requires Authentik API write access.'
  end

  private

  def set_authentik_user
    @authentik_user = AuthentikUser.find(params[:id])
  end
end
