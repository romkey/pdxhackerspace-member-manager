class SheetEntriesController < AuthenticatedController
  def index
    @sheet_entries = SheetEntry.order(Arel.sql("LOWER(name) ASC"))
    @entry_count = @sheet_entries.count
    @with_email_count = SheetEntry.with_email.count
    @paying_count = SheetEntry.where("LOWER(status) = ?", "paying").count
    @sponsored_count = SheetEntry.where("LOWER(status) = ?", "sponsored").count
    @inactive_count = SheetEntry.where("status IS NULL OR status = ''").count

    user_emails = User.where.not(email: nil).pluck(Arel.sql("LOWER(email)"))
    @shared_email_count = if user_emails.any?
                            SheetEntry.where(email: user_emails).count
                          else
                            0
                          end

    user_names = User.where.not(full_name: nil).pluck(Arel.sql("LOWER(full_name)"))
    @shared_name_count = if user_names.any?
                           SheetEntry.where("LOWER(name) IN (?)", user_names).count
                         else
                           0
                         end
  end

  def show
    @sheet_entry = SheetEntry.find(params[:id])
    @payments = PaymentHistory.for_sheet_entry(@sheet_entry)
    
    # Find previous and next entries using the same ordering as index
    ordered_ids = SheetEntry.order(Arel.sql("LOWER(name) ASC")).pluck(:id)
    current_index = ordered_ids.index(@sheet_entry.id)
    
    if current_index
      @previous_sheet_entry = current_index > 0 ? SheetEntry.find(ordered_ids[current_index - 1]) : nil
      @next_sheet_entry = current_index < ordered_ids.length - 1 ? SheetEntry.find(ordered_ids[current_index + 1]) : nil
    else
      @previous_sheet_entry = nil
      @next_sheet_entry = nil
    end
  end

  def sync
    GoogleSheets::SyncJob.perform_later
    redirect_to sheet_entries_path, notice: "Google Sheet sync scheduled."
  end

  def sync_to_users
    linked_count = 0
    created_count = 0
    skipped_count = 0

    SheetEntry.where(user_id: nil).find_each do |sheet_entry|
      # Find matching users by email or name
      matches = []
      
      if sheet_entry.email.present?
        # Match by primary email
        matches += User.where("LOWER(email) = ?", sheet_entry.email.downcase)
        # Match by extra_emails array (check if email exists in the array, case-insensitive)
        matches += User.where("EXISTS (SELECT 1 FROM unnest(extra_emails) AS email WHERE LOWER(email) = ?)", sheet_entry.email.downcase)
      end
      
      if sheet_entry.name.present?
        matches += User.where("LOWER(full_name) = ?", sheet_entry.name.downcase)
      end
      
      # Remove duplicates and get unique matches
      matches = matches.uniq
      
      if matches.count == 1
        # Link to existing user
        user = matches.first
        
        # Link the sheet entry to the user
        sheet_entry.update!(user_id: user.id)
        
        # Handle email differences
        if sheet_entry.email.present?
          # Split email on commas and whitespace, clean and validate each
          email_list = sheet_entry.email.split(/[,;\s]+/).map(&:strip).reject(&:blank?)
          email_list = email_list.select { |e| e.match?(URI::MailTo::EMAIL_REGEXP) }
          
          if email_list.any?
            if user.email.blank?
              # User has no email, set the first one as primary
              user.update!(email: email_list.first)
              # Add remaining emails to extra_emails
              if email_list.length > 1
                extra_emails = user.extra_emails || []
                email_list[1..-1].each do |email|
                  unless extra_emails.map(&:downcase).include?(email.downcase)
                    extra_emails << email
                  end
                end
                user.update!(extra_emails: extra_emails) if extra_emails.length > (user.extra_emails || []).length
              end
            else
              # User has email, add all sheet entry emails to extra_emails if different
              extra_emails = user.extra_emails || []
              email_list.each do |email|
                unless user.email.downcase == email.downcase || extra_emails.map(&:downcase).include?(email.downcase)
                  extra_emails << email
                end
              end
              if extra_emails.length > (user.extra_emails || []).length
                user.update!(extra_emails: extra_emails)
              end
            end
          end
        end
        
        # Update attributes (RFID, trained_on, notes)
        attributes = user.authentik_attributes || {}
        attributes_changed = false
        
        # Copy RFID value into attributes
        if sheet_entry.rfid.present?
          attributes["rfid"] = sheet_entry.rfid
          attributes_changed = true
        end
        
        # Create/update trained_on list from access columns
        trained_on = []
        SheetEntry::ACCESS_COLUMNS.each do |column|
          next if column == :rfid # Skip RFID as it's stored separately
          
          value = sheet_entry[column]
          if value.present?
            trained_on << column.to_s.humanize
          end
        end
        if trained_on.any?
          attributes["trained_on"] = trained_on
          attributes_changed = true
        end
        
        # Handle name differences
        if sheet_entry.name.present? && user.full_name.present? && 
           sheet_entry.name.downcase != user.full_name.downcase
          # Names differ, add a note
          notes = attributes["notes"] || ""
          note_text = "Sheet entry name: #{sheet_entry.name}"
          unless notes.include?(note_text)
            notes = notes.present? ? "#{notes}\n#{note_text}" : note_text
            attributes["notes"] = notes
            attributes_changed = true
          end
        end
        
        # Update user attributes if anything changed
        if attributes_changed
          user.update!(authentik_attributes: attributes)
        end
        
        linked_count += 1
      elsif matches.count == 0
        # Create new user from sheet entry
        attributes = {}
        
        # Copy RFID value into attributes
        if sheet_entry.rfid.present?
          attributes["rfid"] = sheet_entry.rfid
        end
        
        # Create trained_on list from access columns that have values
        trained_on = []
        SheetEntry::ACCESS_COLUMNS.each do |column|
          next if column == :rfid # Skip RFID as it's stored separately
          
          value = sheet_entry[column]
          if value.present?
            trained_on << column.to_s.humanize
          end
        end
        attributes["trained_on"] = trained_on if trained_on.any?
        
        # Generate unique authentik_id
        authentik_id = SecureRandom.uuid
        
        # Handle multiple emails - split on commas and whitespace
        primary_email = nil
        extra_emails = []
        if sheet_entry.email.present?
          email_list = sheet_entry.email.split(/[,;\s]+/).map(&:strip).reject(&:blank?)
          email_list = email_list.select { |e| e.match?(URI::MailTo::EMAIL_REGEXP) }
          if email_list.any?
            primary_email = email_list.first
            extra_emails = email_list[1..-1] if email_list.length > 1
          end
        end
        
        # Create the user
        user = User.create!(
          authentik_id: authentik_id,
          email: primary_email,
          full_name: sheet_entry.name,
          active: true,
          extra_emails: extra_emails,
          authentik_attributes: attributes
        )
        
        # Link the sheet entry to the new user
        sheet_entry.update!(user_id: user.id)
        
        created_count += 1
      else
        # Multiple matches, skip
        skipped_count += 1
      end
    end
    
    parts = []
    parts << "#{linked_count} linked" if linked_count > 0
    parts << "#{created_count} created" if created_count > 0
    parts << "#{skipped_count} skipped" if skipped_count > 0
    
    notice = if parts.any?
               "Sync complete. #{parts.join(', ')}."
             else
               "Sync complete. No changes."
             end
    
    redirect_to sheet_entries_path, notice: notice
  end
end

