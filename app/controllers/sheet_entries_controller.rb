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
    @sheet_entry = SheetEntry.includes(:user).find(params[:id])
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
    updated_count = 0
    skipped_count = 0

    # First, process unlinked entries to link them
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
        
        # Update RFID array - add if not already present
        if sheet_entry.rfid.present?
          rfid_array = user.rfid || []
          unless rfid_array.include?(sheet_entry.rfid)
            rfid_array << sheet_entry.rfid
            user.update!(rfid: rfid_array)
          end
        end
        
        # Update attributes (trained_on, notes)
        attributes = user.authentik_attributes || {}
        attributes_changed = false
        
        # Create trainer_capabilities and training records from access columns
        SheetEntry::ACCESS_COLUMNS.each do |column|
          next if column == :rfid # Skip RFID as it's stored separately
          
          value = sheet_entry[column]
          next unless value.present?
          
          topic_name = column.to_s.humanize
          training_topic = TrainingTopic.find_by(name: topic_name)
          next unless training_topic # Skip if topic doesn't exist
          
          value_normalized = value.to_s.downcase.strip
          
          if value_normalized == "trainer"
            # Create trainer_capability if it doesn't exist
            TrainerCapability.find_or_create_by!(user: user, training_topic: training_topic)
            # Also mark them as trained on this topic
            Training.find_or_create_by!(
              trainee: user,
              trainer: nil,
              training_topic: training_topic
            ) do |training|
              training.trained_at = Time.current
            end
          else
            # Create training record (trained, but trainer unknown)
            Training.find_or_create_by!(
              trainee: user,
              trainer: nil,
              training_topic: training_topic
            ) do |training|
              training.trained_at = Time.current
            end
          end
        end
        
        # Handle name differences
        if sheet_entry.name.present? && user.full_name.present? && 
           sheet_entry.name.downcase != user.full_name.downcase
          # Names differ, add a note
          notes = user.notes || ""
          note_text = "Sheet entry name: #{sheet_entry.name}"
          unless notes.include?(note_text)
            notes = notes.present? ? "#{notes}\n#{note_text}" : note_text
            user.update!(notes: notes)
          end
        end
        
        # Update user attributes if anything changed
        if attributes_changed
          user.update!(authentik_attributes: attributes)
        end
        
        # Update user membership_status based on sheet entry status
        # If status is blank or contains "inactive" (case-insensitive), set user to inactive; otherwise set to active
        is_inactive = sheet_entry.status.blank? || sheet_entry.status.to_s.downcase.include?("inactive")
        membership_status = is_inactive ? "inactive" : "active"
        user.update!(membership_status: membership_status)
        
        # Update payment_type based on sheet entry status
        payment_type = determine_payment_type(sheet_entry.status)
        user.update!(payment_type: payment_type)
        
        linked_count += 1
      elsif matches.count == 0
        # Create new user from sheet entry
        attributes = {}
        
        # Set RFID array
        rfid_array = sheet_entry.rfid.present? ? [sheet_entry.rfid] : []
        
        # Note: trainer_capabilities and training records will be created after user is saved
        
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
        
        # Determine membership_status: inactive if status is blank or contains "inactive" (case-insensitive)
        is_inactive = sheet_entry.status.blank? || sheet_entry.status.to_s.downcase.include?("inactive")
        membership_status = is_inactive ? "inactive" : "active"
        
        # Determine payment_type based on sheet entry status
        payment_type = determine_payment_type(sheet_entry.status)
        
        # Create the user
        user = User.create!(
          authentik_id: authentik_id,
          email: primary_email,
          full_name: sheet_entry.name,
          membership_status: membership_status,
          payment_type: payment_type,
          extra_emails: extra_emails,
          rfid: rfid_array,
          authentik_attributes: attributes
        )
        
        # Link the sheet entry to the new user
        sheet_entry.update!(user_id: user.id)
        
        # Create trainer_capabilities and training records from access columns
        SheetEntry::ACCESS_COLUMNS.each do |column|
          next if column == :rfid # Skip RFID as it's stored separately
          
          value = sheet_entry[column]
          next unless value.present?
          
          topic_name = column.to_s.humanize
          training_topic = TrainingTopic.find_by(name: topic_name)
          next unless training_topic # Skip if topic doesn't exist
          
          value_normalized = value.to_s.downcase.strip
          
          if value_normalized == "trainer"
            # Create trainer_capability
            TrainerCapability.find_or_create_by!(user: user, training_topic: training_topic)
          else
            # Create training record (trained, but trainer unknown)
            Training.find_or_create_by!(
              trainee: user,
              trainer: nil,
              training_topic: training_topic
            ) do |training|
              training.trained_at = Time.current
            end
          end
        end
        
        created_count += 1
      else
        # Multiple matches, skip
        skipped_count += 1
      end
    end
    
    # Then, process already-linked entries to update their status and other fields
    SheetEntry.where.not(user_id: nil).includes(:user).find_each do |sheet_entry|
      user = sheet_entry.user
      next unless user # Skip if user was deleted
      
      # Update user membership_status based on sheet entry status
      # If status is blank or contains "inactive" (case-insensitive), set user to inactive; otherwise set to active
      is_inactive = sheet_entry.status.blank? || sheet_entry.status.to_s.downcase.include?("inactive")
      new_membership_status = is_inactive ? "inactive" : "active"
      status_changed = false
      if user.membership_status != new_membership_status
        user.update!(membership_status: new_membership_status)
        status_changed = true
      end
      
      # Update payment_type based on sheet entry status
      payment_type = determine_payment_type(sheet_entry.status)
      if user.payment_type != payment_type
        user.update!(payment_type: payment_type)
        status_changed = true
      end
      
      if status_changed
        updated_count += 1
      end
      
      # Update RFID array - add if not already present
      if sheet_entry.rfid.present?
        rfid_array = user.rfid || []
        unless rfid_array.include?(sheet_entry.rfid)
          rfid_array << sheet_entry.rfid
          user.update!(rfid: rfid_array)
        end
      end
      
      # Update attributes (trained_on)
      attributes = user.authentik_attributes || {}
      attributes_changed = false
      
      # Create/update trainer_capabilities and training records from access columns
      SheetEntry::ACCESS_COLUMNS.each do |column|
        next if column == :rfid # Skip RFID as it's stored separately
        
        value = sheet_entry[column]
        next unless value.present?
        
        topic_name = column.to_s.humanize
        training_topic = TrainingTopic.find_by(name: topic_name)
        next unless training_topic # Skip if topic doesn't exist
        
        value_normalized = value.to_s.downcase.strip
        
        if value_normalized == "trainer"
          # Create trainer_capability if it doesn't exist
          TrainerCapability.find_or_create_by!(user: user, training_topic: training_topic)
        else
          # Create training record (trained, but trainer unknown)
          Training.find_or_create_by!(
            trainee: user,
            trainer: nil,
            training_topic: training_topic
          ) do |training|
            training.trained_at = Time.current
          end
        end
      end
      
      # Update user attributes if anything changed
      if attributes_changed
        user.update!(authentik_attributes: attributes)
      end
    end
    
    parts = []
    parts << "#{linked_count} linked" if linked_count > 0
    parts << "#{created_count} created" if created_count > 0
    parts << "#{updated_count} updated" if updated_count > 0
    parts << "#{skipped_count} skipped" if skipped_count > 0
    
    notice = if parts.any?
               "Sync complete. #{parts.join(', ')}."
             else
               "Sync complete. No changes."
             end
    
    redirect_to sheet_entries_path, notice: notice
  end

  private

  def determine_payment_type(status)
    return "inactive" if status.blank? || status.to_s.downcase.include?("inactive")
    return "sponsored" if status.to_s.downcase.include?("sponsored")
    "unknown"
  end
end

