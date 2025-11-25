class SheetEntriesController < AdminController
  def index
    @sheet_entries = SheetEntry.order(Arel.sql('LOWER(name) ASC'))
    @entry_count = @sheet_entries.count
    @with_email_count = SheetEntry.with_email.count
    @paying_count = SheetEntry.where('LOWER(status) = ?', 'paying').count
    @sponsored_count = SheetEntry.where('LOWER(status) = ?', 'sponsored').count
    @inactive_count = SheetEntry.where("status IS NULL OR status = ''").count

    user_emails = User.where.not(email: nil).pluck(Arel.sql('LOWER(email)'))
    @shared_email_count = if user_emails.any?
                            SheetEntry.where(email: user_emails).count
                          else
                            0
                          end

    user_names = User.where.not(full_name: nil).pluck(Arel.sql('LOWER(full_name)'))
    @shared_name_count = if user_names.any?
                           SheetEntry.where('LOWER(name) IN (?)', user_names).count
                         else
                           0
                         end
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
    GoogleSheets::SyncJob.perform_later
    redirect_to sheet_entries_path, notice: 'Google Sheet sync scheduled.'
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
        matches += User.where('LOWER(email) = ?', sheet_entry.email.downcase)
        # Match by extra_emails array (check if email exists in the array, case-insensitive)
        matches += User.where('EXISTS (SELECT 1 FROM unnest(extra_emails) AS email WHERE LOWER(email) = ?)',
                              sheet_entry.email.downcase)
      end

      matches += User.where('LOWER(full_name) = ?', sheet_entry.name.downcase) if sheet_entry.name.present?

      # Remove duplicates and get unique matches
      matches = matches.uniq

      if matches.one?
        # Link to existing user
        user = matches.first

        # Link the sheet entry to the user
        sheet_entry.update!(user_id: user.id)

        # Handle email differences
        if sheet_entry.email.present?
          # Split email on commas and whitespace, clean and validate each
          email_list = sheet_entry.email.split(/[,;\s]+/).map(&:strip).compact_blank
          email_list = email_list.grep(URI::MailTo::EMAIL_REGEXP)

          if email_list.any?
            if user.email.blank?
              # User has no email, set the first one as primary
              user.update!(email: email_list.first)
              # Add remaining emails to extra_emails
              if email_list.length > 1
                extra_emails = user.extra_emails || []
                email_list[1..].each do |email|
                  extra_emails << email unless extra_emails.map(&:downcase).include?(email.downcase)
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
              user.update!(extra_emails: extra_emails) if extra_emails.length > (user.extra_emails || []).length
            end
          end
        end

        # Replace all existing RFID records with the one from the sheet entry
        user.rfids.destroy_all
        Rfid.create!(user: user, rfid: sheet_entry.rfid) if sheet_entry.rfid.present?

        # Update attributes (trained_on, notes)
        attributes = user.authentik_attributes || {}
        attributes_changed = false

        # Create trainer_capabilities and training records from access columns
        SheetEntry::ACCESS_COLUMNS.each do |column|
          next if column == :rfid # Skip RFID as it's stored separately

          value = sheet_entry[column]
          next if value.blank?

          topic_name = column.to_s.humanize
          training_topic = TrainingTopic.where('LOWER(name) = ?', topic_name.downcase).first
          next unless training_topic # Skip if topic doesn't exist

          value_normalized = value.to_s.downcase.strip

          if value_normalized == 'trainer'
            # Create trainer_capability if it doesn't exist
            unless TrainerCapability.exists?(user: user, training_topic: training_topic)
              TrainerCapability.create!(user: user, training_topic: training_topic)
              Journal.create!(
                user: user,
                actor_user: Current.user,
                action: 'updated',
                changes_json: {
                  'trainer_capability_added' => {
                    'from' => nil,
                    'to' => training_topic.name
                  }
                },
                changed_at: Time.current
              )
            end
            # Also mark them as trained on this topic
            unless Training.exists?(trainee: user, trainer: nil, training_topic: training_topic)
              Training.create!(
                trainee: user,
                trainer: nil,
                training_topic: training_topic,
                trained_at: Time.current
              )
              Journal.create!(
                user: user,
                actor_user: Current.user,
                action: 'updated',
                changes_json: {
                  'training_added' => {
                    'from' => nil,
                    'to' => training_topic.name
                  }
                },
                changed_at: Time.current
              )
            end
          else
            # Create training record (trained, but trainer unknown)
            unless Training.exists?(trainee: user, trainer: nil, training_topic: training_topic)
              Training.create!(
                trainee: user,
                trainer: nil,
                training_topic: training_topic,
                trained_at: Time.current
              )
              Journal.create!(
                user: user,
                actor_user: Current.user,
                action: 'updated',
                changes_json: {
                  'training_added' => {
                    'from' => nil,
                    'to' => training_topic.name
                  }
                },
                changed_at: Time.current
              )
            end
          end
        end

        # Handle name differences
        if sheet_entry.name.present? && user.full_name.present? &&
           sheet_entry.name.downcase != user.full_name.downcase
          # Names differ, add a note
          notes = user.notes || ''
          note_text = "Sheet entry name: #{sheet_entry.name}"
          unless notes.include?(note_text)
            notes = notes.present? ? "#{notes}\n#{note_text}" : note_text
            user.update!(notes: notes)
          end
        end

        # Update user attributes if anything changed
        user.update!(authentik_attributes: attributes) if attributes_changed

        # Update user active status based on sheet entry status
        # If status is blank or contains "inactive" (case-insensitive), set user to inactive; otherwise set to active
        is_inactive = sheet_entry.status.blank? || sheet_entry.status.to_s.downcase.include?('inactive')
        user.update!(active: !is_inactive)

        # Update payment_type based on sheet entry status
        payment_type = determine_payment_type(sheet_entry.status)
        user.update!(payment_type: payment_type)

        # If payment_type is sponsored, set membership_status to sponsored
        user.update!(membership_status: 'sponsored') if payment_type == 'sponsored'

        linked_count += 1
      elsif matches.none?
        # Create new user from sheet entry
        attributes = {}

        # NOTE: trainer_capabilities and training records will be created after user is saved

        # Handle multiple emails - split on commas and whitespace
        primary_email = nil
        extra_emails = []
        if sheet_entry.email.present?
          email_list = sheet_entry.email.split(/[,;\s]+/).map(&:strip).compact_blank
          email_list = email_list.grep(URI::MailTo::EMAIL_REGEXP)
          if email_list.any?
            primary_email = email_list.first
            extra_emails = email_list[1..] if email_list.length > 1
          end
        end

        # Determine active status: inactive if status is blank or contains "inactive" (case-insensitive)
        is_inactive = sheet_entry.status.blank? || sheet_entry.status.to_s.downcase.include?('inactive')

        # Determine payment_type based on sheet entry status
        payment_type = determine_payment_type(sheet_entry.status)

        # Determine membership_status - set to sponsored if payment_type is sponsored
        membership_status = payment_type == 'sponsored' ? 'sponsored' : 'unknown'

        # Create the user (without authentik_id - it will be set when synced from Authentik)
        user = User.create!(
          email: primary_email,
          full_name: sheet_entry.name,
          active: !is_inactive,
          payment_type: payment_type,
          membership_status: membership_status,
          extra_emails: extra_emails,
          authentik_attributes: attributes
        )

        # Link the sheet entry to the new user
        sheet_entry.update!(user_id: user.id)

        # Create RFID record if present
        Rfid.create!(user: user, rfid: sheet_entry.rfid) if sheet_entry.rfid.present?

        # Create trainer_capabilities and training records from access columns
        SheetEntry::ACCESS_COLUMNS.each do |column|
          next if column == :rfid # Skip RFID as it's stored separately

          value = sheet_entry[column]
          next if value.blank?

          topic_name = column.to_s.humanize
          training_topic = TrainingTopic.where('LOWER(name) = ?', topic_name.downcase).first
          next unless training_topic # Skip if topic doesn't exist

          value_normalized = value.to_s.downcase.strip

          if value_normalized == 'trainer'
            # Create trainer_capability
            unless TrainerCapability.exists?(user: user, training_topic: training_topic)
              TrainerCapability.create!(user: user, training_topic: training_topic)
              Journal.create!(
                user: user,
                actor_user: Current.user,
                action: 'updated',
                changes_json: {
                  'trainer_capability_added' => {
                    'from' => nil,
                    'to' => training_topic.name
                  }
                },
                changed_at: Time.current
              )
            end
          else
            # Create training record (trained, but trainer unknown)
            unless Training.exists?(trainee: user, trainer: nil, training_topic: training_topic)
              Training.create!(
                trainee: user,
                trainer: nil,
                training_topic: training_topic,
                trained_at: Time.current
              )
              Journal.create!(
                user: user,
                actor_user: Current.user,
                action: 'updated',
                changes_json: {
                  'training_added' => {
                    'from' => nil,
                    'to' => training_topic.name
                  }
                },
                changed_at: Time.current
              )
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

      # Update user active status based on sheet entry status
      # If status is blank or contains "inactive" (case-insensitive), set user to inactive; otherwise set to active
      is_inactive = sheet_entry.status.blank? || sheet_entry.status.to_s.downcase.include?('inactive')
      new_active = !is_inactive
      status_changed = false
      if user.active != new_active
        user.update!(active: new_active)
        status_changed = true
      end

      # Update payment_type based on sheet entry status
      payment_type = determine_payment_type(sheet_entry.status)
      if user.payment_type != payment_type
        user.update!(payment_type: payment_type)
        status_changed = true
      end

      # If payment_type is sponsored, set membership_status to sponsored
      if payment_type == 'sponsored' && user.membership_status != 'sponsored'
        user.update!(membership_status: 'sponsored')
        status_changed = true
      end

      updated_count += 1 if status_changed

      # Replace all existing RFID records with the one from the sheet entry
      user.rfids.destroy_all
      Rfid.create!(user: user, rfid: sheet_entry.rfid) if sheet_entry.rfid.present?

      # Update attributes (trained_on)
      attributes = user.authentik_attributes || {}
      attributes_changed = false

      # Create/update trainer_capabilities and training records from access columns
      SheetEntry::ACCESS_COLUMNS.each do |column|
        next if column == :rfid # Skip RFID as it's stored separately

        value = sheet_entry[column]
        next if value.blank?

        topic_name = column.to_s.humanize
        training_topic = TrainingTopic.where('LOWER(name) = ?', topic_name.downcase).first
        next unless training_topic # Skip if topic doesn't exist

        value_normalized = value.to_s.downcase.strip

        if value_normalized == 'trainer'
          # Create trainer_capability if it doesn't exist
          unless TrainerCapability.exists?(user: user, training_topic: training_topic)
            TrainerCapability.create!(user: user, training_topic: training_topic)
            Journal.create!(
              user: user,
              actor_user: Current.user,
              action: 'updated',
              changes_json: {
                'trainer_capability_added' => {
                  'from' => nil,
                  'to' => training_topic.name
                }
              },
              changed_at: Time.current
            )
          end
        else
          # Create training record (trained, but trainer unknown)
          unless Training.exists?(trainee: user, trainer: nil, training_topic: training_topic)
            Training.create!(
              trainee: user,
              trainer: nil,
              training_topic: training_topic,
              trained_at: Time.current
            )
            Journal.create!(
              user: user,
              actor_user: Current.user,
              action: 'updated',
              changes_json: {
                'training_added' => {
                  'from' => nil,
                  'to' => training_topic.name
                }
              },
              changed_at: Time.current
            )
          end
        end
      end

      # Update user attributes if anything changed
      user.update!(authentik_attributes: attributes) if attributes_changed
    end

    parts = []
    parts << "#{linked_count} linked" if linked_count.positive?
    parts << "#{created_count} created" if created_count.positive?
    parts << "#{updated_count} updated" if updated_count.positive?
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
    linked = false
    created = false
    updated = false

    # If already linked, update the linked user
    if @sheet_entry.user_id.present?
      user = @sheet_entry.user

      # Handle email differences
      if @sheet_entry.email.present?
        # Split email on commas and whitespace, clean and validate each
        email_list = @sheet_entry.email.split(/[,;\s]+/).map(&:strip).compact_blank
        email_list = email_list.grep(URI::MailTo::EMAIL_REGEXP)

        if email_list.any?
          if user.email.blank?
            # User has no email, set the first one as primary
            user.update!(email: email_list.first)
            # Add remaining emails to extra_emails
            if email_list.length > 1
              extra_emails = user.extra_emails || []
              email_list[1..].each do |email|
                extra_emails << email unless extra_emails.map(&:downcase).include?(email.downcase)
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
            user.update!(extra_emails: extra_emails) if extra_emails.length > (user.extra_emails || []).length
          end
        end
      end

      # Replace all existing RFID records with the one from the sheet entry
      user.rfids.destroy_all
      Rfid.create!(user: user, rfid: @sheet_entry.rfid) if @sheet_entry.rfid.present?

      # Create trainer_capabilities and training records from access columns
      SheetEntry::ACCESS_COLUMNS.each do |column|
        next if column == :rfid # Skip RFID as it's stored separately

        value = @sheet_entry[column]
        next if value.blank?

        topic_name = column.to_s.humanize
        training_topic = TrainingTopic.where('LOWER(name) = ?', topic_name.downcase).first
        next unless training_topic # Skip if topic doesn't exist

        value_normalized = value.to_s.downcase.strip

        if value_normalized == 'trainer'
          # Create trainer_capability if it doesn't exist
          unless TrainerCapability.exists?(user: user, training_topic: training_topic)
            TrainerCapability.create!(user: user, training_topic: training_topic)
            Journal.create!(
              user: user,
              actor_user: Current.user,
              action: 'updated',
              changes_json: {
                'trainer_capability_added' => {
                  'from' => nil,
                  'to' => training_topic.name
                }
              },
              changed_at: Time.current
            )
          end
          # Also mark them as trained on this topic
          unless Training.exists?(trainee: user, trainer: nil, training_topic: training_topic)
            Training.create!(
              trainee: user,
              trainer: nil,
              training_topic: training_topic,
              trained_at: Time.current
            )
            Journal.create!(
              user: user,
              actor_user: Current.user,
              action: 'updated',
              changes_json: {
                'training_added' => {
                  'from' => nil,
                  'to' => training_topic.name
                }
              },
              changed_at: Time.current
            )
          end
        else
          # Create training record (trained, but trainer unknown)
          unless Training.exists?(trainee: user, trainer: nil, training_topic: training_topic)
            Training.create!(
              trainee: user,
              trainer: nil,
              training_topic: training_topic,
              trained_at: Time.current
            )
            Journal.create!(
              user: user,
              actor_user: Current.user,
              action: 'updated',
              changes_json: {
                'training_added' => {
                  'from' => nil,
                  'to' => training_topic.name
                }
              },
              changed_at: Time.current
            )
          end
        end
      end

      # Handle name differences
      if @sheet_entry.name.present? && user.full_name.present? &&
         @sheet_entry.name.downcase != user.full_name.downcase
        # Names differ, add a note
        notes = user.notes || ''
        note_text = "Sheet entry name: #{@sheet_entry.name}"
        unless notes.include?(note_text)
          notes = notes.present? ? "#{notes}\n#{note_text}" : note_text
          user.update!(notes: notes)
        end
      end

      # Update user active status based on sheet entry status
      is_inactive = @sheet_entry.status.blank? || @sheet_entry.status.to_s.downcase.include?('inactive')
      new_active = !is_inactive
      if user.active != new_active
        user.update!(active: new_active)
        updated = true
      end

      # Update payment_type based on sheet entry status
      payment_type = determine_payment_type(@sheet_entry.status)
      if user.payment_type != payment_type
        user.update!(payment_type: payment_type)
        updated = true
      end

      # If payment_type is sponsored, set membership_status to sponsored
      if payment_type == 'sponsored' && user.membership_status != 'sponsored'
        user.update!(membership_status: 'sponsored')
        updated = true
      end

      # Build notice message
      notice = updated ? 'Sync complete. Updated user.' : 'Sync complete. No changes.'
      redirect_to sheet_entry_path(@sheet_entry), notice: notice
      return
    end

    # Not linked - find matching users by email or name
    matches = []

    if @sheet_entry.email.present?
      # Match by primary email
      matches += User.where('LOWER(email) = ?', @sheet_entry.email.downcase)
      # Match by extra_emails array (check if email exists in the array, case-insensitive)
      matches += User.where('EXISTS (SELECT 1 FROM unnest(extra_emails) AS email WHERE LOWER(email) = ?)',
                            @sheet_entry.email.downcase)
    end

    matches += User.where('LOWER(full_name) = ?', @sheet_entry.name.downcase) if @sheet_entry.name.present?

    # Remove duplicates and get unique matches
    matches = matches.uniq

    if matches.one?
      # Link to existing user
      user = matches.first

      # Link the sheet entry to the user
      @sheet_entry.update!(user_id: user.id)
      linked = true

      # Handle email differences
      if @sheet_entry.email.present?
        # Split email on commas and whitespace, clean and validate each
        email_list = @sheet_entry.email.split(/[,;\s]+/).map(&:strip).compact_blank
        email_list = email_list.grep(URI::MailTo::EMAIL_REGEXP)

        if email_list.any?
          if user.email.blank?
            # User has no email, set the first one as primary
            user.update!(email: email_list.first)
            # Add remaining emails to extra_emails
            if email_list.length > 1
              extra_emails = user.extra_emails || []
              email_list[1..].each do |email|
                extra_emails << email unless extra_emails.map(&:downcase).include?(email.downcase)
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
            user.update!(extra_emails: extra_emails) if extra_emails.length > (user.extra_emails || []).length
          end
        end
      end

      # Replace all existing RFID records with the one from the sheet entry
      user.rfids.destroy_all
      Rfid.create!(user: user, rfid: @sheet_entry.rfid) if @sheet_entry.rfid.present?

      # Create trainer_capabilities and training records from access columns
      SheetEntry::ACCESS_COLUMNS.each do |column|
        next if column == :rfid # Skip RFID as it's stored separately

        value = @sheet_entry[column]
        next if value.blank?

        topic_name = column.to_s.humanize
        training_topic = TrainingTopic.where('LOWER(name) = ?', topic_name.downcase).first
        next unless training_topic # Skip if topic doesn't exist

        value_normalized = value.to_s.downcase.strip

        if value_normalized == 'trainer'
          # Create trainer_capability if it doesn't exist
          unless TrainerCapability.exists?(user: user, training_topic: training_topic)
            TrainerCapability.create!(user: user, training_topic: training_topic)
            Journal.create!(
              user: user,
              actor_user: Current.user,
              action: 'updated',
              changes_json: {
                'trainer_capability_added' => {
                  'from' => nil,
                  'to' => training_topic.name
                }
              },
              changed_at: Time.current
            )
          end
          # Also mark them as trained on this topic
          unless Training.exists?(trainee: user, trainer: nil, training_topic: training_topic)
            Training.create!(
              trainee: user,
              trainer: nil,
              training_topic: training_topic,
              trained_at: Time.current
            )
            Journal.create!(
              user: user,
              actor_user: Current.user,
              action: 'updated',
              changes_json: {
                'training_added' => {
                  'from' => nil,
                  'to' => training_topic.name
                }
              },
              changed_at: Time.current
            )
          end
        else
          # Create training record (trained, but trainer unknown)
          unless Training.exists?(trainee: user, trainer: nil, training_topic: training_topic)
            Training.create!(
              trainee: user,
              trainer: nil,
              training_topic: training_topic,
              trained_at: Time.current
            )
            Journal.create!(
              user: user,
              actor_user: Current.user,
              action: 'updated',
              changes_json: {
                'training_added' => {
                  'from' => nil,
                  'to' => training_topic.name
                }
              },
              changed_at: Time.current
            )
          end
        end
      end

      # Handle name differences
      if @sheet_entry.name.present? && user.full_name.present? &&
         @sheet_entry.name.downcase != user.full_name.downcase
        # Names differ, add a note
        notes = user.notes || ''
        note_text = "Sheet entry name: #{@sheet_entry.name}"
        unless notes.include?(note_text)
          notes = notes.present? ? "#{notes}\n#{note_text}" : note_text
          user.update!(notes: notes)
        end
      end

      # Update user active status based on sheet entry status
      is_inactive = @sheet_entry.status.blank? || @sheet_entry.status.to_s.downcase.include?('inactive')
      new_active = !is_inactive
      if user.active != new_active
        user.update!(active: new_active)
        updated = true
      end

      # Update payment_type based on sheet entry status
      payment_type = determine_payment_type(@sheet_entry.status)
      if user.payment_type != payment_type
        user.update!(payment_type: payment_type)
        updated = true
      end

      # If payment_type is sponsored, set membership_status to sponsored
      if payment_type == 'sponsored' && user.membership_status != 'sponsored'
        user.update!(membership_status: 'sponsored')
        updated = true
      end

    elsif matches.none?
      # Create new user from sheet entry
      attributes = {}

      # Handle multiple emails - split on commas and whitespace
      primary_email = nil
      extra_emails = []
      if @sheet_entry.email.present?
        email_list = @sheet_entry.email.split(/[,;\s]+/).map(&:strip).compact_blank
        email_list = email_list.grep(URI::MailTo::EMAIL_REGEXP)
        if email_list.any?
          primary_email = email_list.first
          extra_emails = email_list[1..] if email_list.length > 1
        end
      end

      # Determine active status: inactive if status is blank or contains "inactive" (case-insensitive)
      is_inactive = @sheet_entry.status.blank? || @sheet_entry.status.to_s.downcase.include?('inactive')

      # Determine payment_type based on sheet entry status
      payment_type = determine_payment_type(@sheet_entry.status)

      # Determine membership_status - set to sponsored if payment_type is sponsored
      membership_status = payment_type == 'sponsored' ? 'sponsored' : 'unknown'

      # Create the user (without authentik_id - it will be set when synced from Authentik)
      user = User.create!(
        email: primary_email,
        full_name: @sheet_entry.name,
        active: !is_inactive,
        payment_type: payment_type,
        membership_status: membership_status,
        extra_emails: extra_emails,
        authentik_attributes: attributes
      )

      # Link the sheet entry to the new user
      @sheet_entry.update!(user_id: user.id)
      created = true

      # Create RFID record if present
      Rfid.create!(user: user, rfid: @sheet_entry.rfid) if @sheet_entry.rfid.present?

      # Create trainer_capabilities and training records from access columns
      SheetEntry::ACCESS_COLUMNS.each do |column|
        next if column == :rfid # Skip RFID as it's stored separately

        value = @sheet_entry[column]
        next if value.blank?

        topic_name = column.to_s.humanize
        training_topic = TrainingTopic.where('LOWER(name) = ?', topic_name.downcase).first
        next unless training_topic # Skip if topic doesn't exist

        value_normalized = value.to_s.downcase.strip

        if value_normalized == 'trainer'
          # Create trainer_capability if it doesn't exist
          unless TrainerCapability.exists?(user: user, training_topic: training_topic)
            TrainerCapability.create!(user: user, training_topic: training_topic)
            Journal.create!(
              user: user,
              actor_user: Current.user,
              action: 'updated',
              changes_json: {
                'trainer_capability_added' => {
                  'from' => nil,
                  'to' => training_topic.name
                }
              },
              changed_at: Time.current
            )
          end
          # Also mark them as trained on this topic
          unless Training.exists?(trainee: user, trainer: nil, training_topic: training_topic)
            Training.create!(
              trainee: user,
              trainer: nil,
              training_topic: training_topic,
              trained_at: Time.current
            )
            Journal.create!(
              user: user,
              actor_user: Current.user,
              action: 'updated',
              changes_json: {
                'training_added' => {
                  'from' => nil,
                  'to' => training_topic.name
                }
              },
              changed_at: Time.current
            )
          end
        else
          # Create training record (trained, but trainer unknown)
          unless Training.exists?(trainee: user, trainer: nil, training_topic: training_topic)
            Training.create!(
              trainee: user,
              trainer: nil,
              training_topic: training_topic,
              trained_at: Time.current
            )
            Journal.create!(
              user: user,
              actor_user: Current.user,
              action: 'updated',
              changes_json: {
                'training_added' => {
                  'from' => nil,
                  'to' => training_topic.name
                }
              },
              changed_at: Time.current
            )
          end
        end
      end
    else
      # Multiple matches - can't determine which one to link to
      redirect_to sheet_entry_path(@sheet_entry),
                  alert: 'Multiple users match this sheet entry. Cannot automatically sync.'
      return
    end

    # Build notice message
    parts = []
    parts << 'linked to existing user' if linked
    parts << 'created new user' if created
    parts << 'updated user' if updated

    notice = if parts.any?
               "Sync complete. #{parts.join(', ')}."
             else
               'Sync complete. No changes.'
             end

    redirect_to sheet_entry_path(@sheet_entry), notice: notice
  end

  def test
    @name_mismatches = []
    @email_mismatches = []
    @rfid_mismatches = []
    @duplicate_rfids = []

    # Find Sheet Entries with same name as Users but different email
    SheetEntry.where.not(email: nil).find_each do |sheet_entry|
      next if sheet_entry.name.blank?

      # Find users with matching name (case-insensitive)
      matching_users = User.where('LOWER(full_name) = ?', sheet_entry.name.downcase)
                           .where.not(email: nil)

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

  def determine_payment_type(status)
    return 'inactive' if status.blank? || status.to_s.downcase.include?('inactive')
    return 'sponsored' if status.to_s.downcase.include?('sponsored')

    'unknown'
  end
end
