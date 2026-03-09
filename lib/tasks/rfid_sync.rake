namespace :rfid do
  desc 'Preview overwriting Member RFID values from linked Sheet entries'
  task preview: :environment do
    RfidSheetSyncer.new(dry_run: true).run
  end

  desc 'Overwrite all Member RFID values from their linked Sheet entries'
  task sync_from_sheet: :environment do
    RfidSheetSyncer.new(dry_run: false).run
  end
end

class RfidSheetSyncer
  def initialize(dry_run: true)
    @dry_run = dry_run
    @updated = 0
    @cleared = 0
    @unchanged = 0
    @skipped_no_sheet = 0
  end

  def run
    puts "#{'[DRY RUN] ' if @dry_run}Syncing Member RFID values from Sheet entries..."
    puts

    User.includes(:sheet_entry, :rfids).find_each do |user|
      sheet = user.sheet_entry

      unless sheet
        @skipped_no_sheet += 1
        next
      end

      current_rfids = user.rfids.map(&:rfid).sort
      sheet_rfid = sheet.rfid.presence

      if sheet_rfid
        if current_rfids == [sheet_rfid]
          @unchanged += 1
          next
        end

        @updated += 1
        old_display = current_rfids.any? ? current_rfids.join(', ') : '(none)'
        action = @dry_run ? 'WOULD UPDATE' : 'UPDATING'
        puts "  #{action} #{user.display_name} " \
             "(#{user.email || 'no email'}): #{old_display} -> #{sheet_rfid}"

        unless @dry_run
          user.rfids.destroy_all
          Rfid.create!(user: user, rfid: sheet_rfid)
        end
      else
        if current_rfids.empty?
          @unchanged += 1
          next
        end

        @cleared += 1
        action = @dry_run ? 'WOULD CLEAR' : 'CLEARING'
        puts "  #{action} #{user.display_name} " \
             "(#{user.email || 'no email'}): #{current_rfids.join(', ')} -> (none)"

        user.rfids.destroy_all unless @dry_run
      end
    end

    puts
    puts 'Summary:'
    puts "  #{@dry_run ? 'Would update' : 'Updated'}: #{@updated}"
    puts "  #{@dry_run ? 'Would clear' : 'Cleared'}: #{@cleared}"
    puts "  Unchanged: #{@unchanged}"
    puts "  Skipped (no linked sheet entry): #{@skipped_no_sheet}"
  end
end
