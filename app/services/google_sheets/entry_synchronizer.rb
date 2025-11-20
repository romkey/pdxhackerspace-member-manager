module GoogleSheets
  class EntrySynchronizer
    MEMBER_HEADER_MAP = {
      'name' => :name,
      'dirty' => :dirty,
      'status' => :status,
      'twitter' => :twitter,
      'alias' => :alias_name,
      'email' => :email,
      'date added' => :date_added,
      'payment' => :payment,
      'paypal name' => :paypal_name,
      'notes' => :notes
    }.freeze

    ACCESS_HEADER_MAP = {
      'name' => :name,
      'dirty' => :dirty,
      'status' => :status,
      'rfid' => :rfid,
      'laser' => :laser,
      'sewing machine' => :sewing_machine,
      'serger' => :serger,
      'embroidery machine' => :embroidery_machine,
      'dremel' => :dremel,
      'ender' => :ender,
      'prusa' => :prusa,
      'laminator' => :laminator,
      'shaper' => :shaper,
      'general shop' => :general_shop,
      'event host' => :event_host,
      'vinyl cutter' => :vinyl_cutter,
      'mpcnc marlin' => :mpcnc_marlin,
      'longmill' => :longmill
    }.freeze

    def initialize(client: Client.new, logger: Rails.logger)
      @client = client
      @logger = logger
    end

    def call
      raise ArgumentError, 'Google Sheets not enabled' unless GoogleSheetsConfig.enabled?

      members = parse_rows(@client.fetch_sheet(Client::MEMBER_LIST_TAB), MEMBER_HEADER_MAP)
      access = parse_rows(@client.fetch_sheet(Client::ACCESS_TAB), ACCESS_HEADER_MAP)

      merged = merge_rows(members, access)
      upsert_entries(merged)
      merged.size
    end

    private

    def parse_rows(values, header_map)
      return [] if values.blank?

      headers = values.first&.map { |h| header_map[h.to_s.strip.downcase] }
      data_rows = values[1..] || []

      data_rows.map do |row|
        row_hash = {}
        headers.each_with_index do |key, idx|
          next if key.nil?

          row_hash[key] = row[idx]
        end
        row_hash.compact_blank
      end.reject(&:empty?)
    end

    def merge_rows(member_rows, access_rows)
      lookup = {}

      member_rows.each do |row|
        register_lookup(lookup, row)
      end

      access_rows.each do |row|
        entry = find_lookup_entry(lookup, row)
        if entry
          entry.merge!(row)
        else
          register_lookup(lookup, row)
        end
      end

      lookup.values.uniq
    end

    def register_lookup(lookup, row)
      if (email = email_key(row))
        lookup[email] = row
      end
      if (name = name_key(row))
        lookup[name] ||= row
      end
    end

    def find_lookup_entry(lookup, row)
      lookup[email_key(row)] || lookup[name_key(row)]
    end

    def email_key(row)
      row[:email].presence&.downcase
    end

    def name_key(row)
      row[:name].presence&.downcase
    end

    def upsert_entries(entries)
      timestamp = Time.current

      SheetEntry.transaction do
        entries.each do |attrs|
          record = find_existing_entry(attrs)
          record ||= SheetEntry.new
          record.assign_attributes(filtered_attributes(attrs))
          record.raw_attributes = attrs
          record.last_synced_at = timestamp
          record.save!
          ensure_user_active_state(record)
        rescue ActiveRecord::RecordInvalid => e
          @logger.error("Failed to sync SheetEntry #{attrs.inspect}: #{e.message}")
        end
      end
    end

    def find_existing_entry(attrs)
      if attrs[:email].present?
        SheetEntry.find_by(email: attrs[:email].strip.downcase)
      elsif attrs[:name].present?
        SheetEntry.find_by(name: attrs[:name])
      end
    end

    def filtered_attributes(attrs)
      attrs.slice(
        :name,
        :dirty,
        :status,
        :twitter,
        :alias_name,
        :email,
        :payment,
        :paypal_name,
        :notes,
        :rfid,
        :laser,
        :sewing_machine,
        :serger,
        :embroidery_machine,
        :dremel,
        :ender,
        :prusa,
        :laminator,
        :shaper,
        :general_shop,
        :event_host,
        :vinyl_cutter,
        :mpcnc_marlin,
        :longmill
      ).tap do |hash|
        hash[:email] = attrs[:email].to_s.strip.presence
        hash[:date_added] = parse_date(attrs[:date_added])
      end
    end

    def parse_date(value)
      return if value.blank?

      Time.zone.parse(value)
    rescue ArgumentError
      nil
    end

    # If a sheet entry has a blank status, treat as inactive and reflect that on the matching user (by email).
    def ensure_user_active_state(sheet_entry)
      email = sheet_entry.email.to_s.strip.downcase
      return if email.blank?

      return if sheet_entry.status.to_s.strip.present?

      user = User.where('LOWER(email) = ?', email).first
      return unless user

      # Mark user inactive if status is blank
      user.update_columns(active: false, updated_at: Time.current)
    end
  end
end
