class SheetEntriesController < AdminController
  def index
    # Base query
    base_query = SheetEntry.order(Arel.sql('LOWER(name) ASC'))

    # Counts for all records
    @total_count = SheetEntry.count
    @with_email_count = SheetEntry.with_email.count
    @paying_count = SheetEntry.where('LOWER(status) = ?', 'paying').count
    @sponsored_count = SheetEntry.where('LOWER(status) = ?', 'sponsored').count
    @inactive_count = SheetEntry.where("status IS NULL OR status = ''").count
    @linked_count = SheetEntry.where.not(user_id: nil).count
    @unlinked_count = SheetEntry.where(user_id: nil).count

    user_emails = User.where.not(email: nil).pluck(Arel.sql('LOWER(email)'))
    @shared_email_count = if user_emails.any?
                            SheetEntry.where(email: user_emails).count
                          else
                            0
                          end

    # Only count multi-word name matches to avoid false positives on common first names
    user_names = User.where.not(full_name: nil)
                     .where("full_name LIKE '% %'")
                     .pluck(Arel.sql('LOWER(full_name)'))
    @shared_name_count = if user_names.any?
                           SheetEntry.where("name LIKE '% %'")
                                     .where('LOWER(name) IN (?)', user_names).count
                         else
                           0
                         end

    # Apply filters
    @sheet_entries = case params[:filter]
                     when 'linked'
                       base_query.where.not(user_id: nil)
                     when 'unlinked'
                       base_query.where(user_id: nil)
                     when 'paying'
                       base_query.where('LOWER(status) = ?', 'paying')
                     when 'sponsored'
                       base_query.where('LOWER(status) = ?', 'sponsored')
                     when 'inactive'
                       base_query.where("status IS NULL OR status = ''")
                     when 'with_email'
                       base_query.with_email
                     else
                       base_query
                     end

    @filter_active = params[:filter].present?
  end

  def show
    @sheet_entry = SheetEntry.includes(:user).find(params[:id])
    @payments = PaymentHistory.for_sheet_entry(@sheet_entry)

    # Find previous and next entries using the same ordering as index
    ordered_ids = SheetEntry.order(Arel.sql('LOWER(name) ASC')).pluck(:id)
    current_index = ordered_ids.index(@sheet_entry.id)

    if current_index
      @previous_sheet_entry = current_index.positive? ? SheetEntry.find(ordered_ids[current_index - 1]) : nil
      @next_sheet_entry = current_index < ordered_ids.length - 1 ? SheetEntry.find(ordered_ids[current_index + 1]) : nil
    else
      @previous_sheet_entry = nil
      @next_sheet_entry = nil
    end
  end

  def sync
    unless MemberSource.enabled?('sheet')
      redirect_to sheet_entries_path, alert: 'Google Sheet source is disabled.'
      return
    end

    GoogleSheets::SyncJob.perform_later
    redirect_to sheet_entries_path, notice: 'Google Sheet sync scheduled.'
  end

  def sync_to_users
    unless MemberSource.enabled?('sheet')
      redirect_to sheet_entries_path, alert: 'Google Sheet source is disabled.'
      return
    end

    linked_count = 0
    skipped_count = 0

    SheetEntry.where(user_id: nil).find_each do |sheet_entry|
      matches = matching_users_for(sheet_entry)
      if matches.one?
        sheet_entry.update!(user_id: matches.first.id)
        linked_count += 1
      else
        skipped_count += 1
      end
    end

    parts = []
    parts << "#{linked_count} linked" if linked_count.positive?
    parts << "#{skipped_count} skipped" if skipped_count.positive?

    notice = if parts.any?
               "Sync complete. #{parts.join(', ')}."
             else
               'Sync complete. No changes.'
             end

    redirect_to sheet_entries_path, notice: notice
  end

  def sync_to_user
    @sheet_entry = SheetEntry.find(params[:id])
    if @sheet_entry.user_id.present?
      notice = 'Sync complete. Sheet entry is already linked.'
      redirect_to sheet_entry_path(@sheet_entry), notice: notice
      return
    end

    matches = matching_users_for(@sheet_entry)

    if matches.one?
      @sheet_entry.update!(user_id: matches.first.id)
      redirect_to sheet_entry_path(@sheet_entry), notice: 'Sync complete. Linked to existing member.'
    elsif matches.none?
      redirect_to sheet_entry_path(@sheet_entry), alert: 'No matching member found. Sheet sync will not create members.'
    else
      redirect_to sheet_entry_path(@sheet_entry),
                  alert: 'Multiple members match this sheet entry. Cannot automatically sync.'
    end
  end

  def unlink_user
    @sheet_entry = SheetEntry.find(params[:id])
    user = @sheet_entry.user

    if user.blank?
      redirect_to sheet_entry_path(@sheet_entry), alert: 'Sheet entry is not linked to a member.'
      return
    end

    @sheet_entry.update!(user_id: nil)
    MemberSource.for('sheet').refresh_statistics!
    redirect_to sheet_entry_path(@sheet_entry), notice: "Disassociated from #{user.display_name}."
  end

  def test
    @name_mismatches = []
    @email_mismatches = []
    @rfid_mismatches = []
    @duplicate_rfids = []

    # Find Sheet Entries with same name as Users but different email
    SheetEntry.where.not(email: nil).find_each do |sheet_entry|
      next if sheet_entry.name.blank?

      # Find users with matching name or alias (skip single-word names)
      matching_users = User.by_name_or_alias(sheet_entry.name).where.not(email: nil)

      matching_users.each do |user|
        # Check if emails are different (case-insensitive)
        next unless user.email.present? && sheet_entry.email.present? &&
                    user.email.downcase != sheet_entry.email.downcase

        @name_mismatches << {
          sheet_entry: sheet_entry,
          user: user,
          sheet_email: sheet_entry.email,
          user_email: user.email
        }
      end

      # Find Sheet Entries with same email as Users but different name
      next if sheet_entry.email.blank?

      # Find users with matching email (case-insensitive)
      matching_users = User.where('LOWER(email) = ?', sheet_entry.email.downcase)
                           .where.not(full_name: nil)

      matching_users.each do |user|
        # Check if names are different (case-insensitive)
        next unless user.full_name.present? && sheet_entry.name.present? &&
                    user.full_name.downcase != sheet_entry.name.downcase

        @email_mismatches << {
          sheet_entry: sheet_entry,
          user: user,
          sheet_name: sheet_entry.name,
          user_name: user.full_name
        }
      end
    end

    # Find Sheet Entries with RFID and check for mismatches with Users
    SheetEntry.where.not(rfid: nil).where.not(rfid: '').find_each do |sheet_entry|
      next if sheet_entry.rfid.blank?

      # Find users with matching RFID (case-insensitive)
      matching_rfids = Rfid.where('LOWER(rfid) = ?', sheet_entry.rfid.downcase).includes(:user)

      matching_rfids.each do |rfid_record|
        user = rfid_record.user
        next unless user

        # Check if name doesn't match (if both are set)
        name_mismatch = false
        if user.full_name.present? && sheet_entry.name.present? &&
           user.full_name.downcase != sheet_entry.name.downcase
          name_mismatch = true
        end

        # Check if email doesn't match (if both are set)
        email_mismatch = false
        if user.email.present? && sheet_entry.email.present? &&
           user.email.downcase != sheet_entry.email.downcase
          email_mismatch = true
        end

        # Add to mismatches if either name or email doesn't match
        next unless name_mismatch || email_mismatch

        # Check if user's name or email exists in any Sheet Entry
        name_in_sheet = user.full_name.present? &&
                        SheetEntry.exists?(['LOWER(name) = ?', user.full_name.downcase])
        email_in_sheet = user.email.present? &&
                         SheetEntry.exists?(['LOWER(email) = ?', user.email.downcase])
        not_in_sheet = !name_in_sheet && !email_in_sheet

        @rfid_mismatches << {
          sheet_entry: sheet_entry,
          user: user,
          rfid: sheet_entry.rfid,
          sheet_name: sheet_entry.name,
          user_name: user.full_name,
          sheet_email: sheet_entry.email,
          user_email: user.email,
          name_mismatch: name_mismatch,
          email_mismatch: email_mismatch,
          not_in_sheet: not_in_sheet
        }
      end
    end

    # Find duplicate RFID values within Sheet Entries
    rfid_counts = SheetEntry.where.not(rfid: nil).where.not(rfid: '')
                            .group('LOWER(rfid)')
                            .having('COUNT(*) > 1')
                            .count

    rfid_counts.each do |rfid_lower, count|
      # Find all sheet entries with this RFID (case-insensitive)
      entries = SheetEntry.where('LOWER(rfid) = ?', rfid_lower)
      @duplicate_rfids << {
        rfid: entries.first.rfid, # Use the actual case from first entry
        entries: entries.to_a,
        count: count
      }
    end
  end

  private

  def matching_users_for(sheet_entry)
    matches = []

    if sheet_entry.email.present?
      normalized_email = sheet_entry.email.downcase
      matches += User.where('LOWER(email) = ?', normalized_email)
      matches += User.where('EXISTS (SELECT 1 FROM unnest(extra_emails) AS email WHERE LOWER(email) = ?)',
                            normalized_email)
    end

    matches += User.by_name_or_alias(sheet_entry.name) if sheet_entry.name.present?
    matches.uniq
  end
end
