# frozen_string_literal: true

require 'csv'

module MembershipApplications
  # Imports historical membership application rows from CSV exports.
  # Does not call +submit!+, +approve!+, or +reject!+ — no journal entries and no mail side effects.
  class CsvImporter
    # Full header strings as they appear in CSVs (do not use %w[Email Address] — that splits).
    RESERVED_HEADERS = ['Approved', 'Timestamp', 'Email Address'].freeze

    def initialize(imported_by: nil, logger: Rails.logger)
      @imported_by = imported_by
      @logger = logger
      @question_ids_by_label = ApplicationFormQuestion.pluck(:label, :id).to_h
    end

    # @param file [#read] uploaded file or StringIO
    # @return [Hash] { imported: Integer, skipped: Integer, errors: Array<String> }
    def call(file)
      raise ArgumentError, 'CSV file is missing' if file.blank?

      csv_content = file.read.force_encoding('UTF-8')
      csv_content = csv_content.sub(/\A\uFEFF/, '')
      csv_data = CSV.parse(csv_content, headers: true)

      counts = { imported: 0, skipped: 0 }
      errors = []

      MembershipApplication.transaction do
        csv_data.each_with_index do |row, idx|
          line = idx + 2
          import_row(row, line, counts, errors)
        rescue StandardError => e
          counts[:skipped] += 1
          errors << "Row #{line}: #{e.message}"
          @logger.error("Membership application CSV row #{line}: #{e.message}")
        end
      end

      { imported: counts[:imported], skipped: counts[:skipped], errors: errors }
    end

    private

    def import_row(row, line, counts, errors)
      row_hash = row.to_h.transform_keys { |k| k.to_s.strip }
      email = row_hash['Email Address']&.strip
      if email.blank?
        counts[:skipped] += 1
        errors << "Row #{line}: missing Email Address"
        return
      end

      submitted_at = parse_timestamp(row_hash['Timestamp'])
      status, rev_at, approved_notes = interpret_approved(row_hash['Approved'])
      reviewed_at = finalize_reviewed_at(status, rev_at, submitted_at)
      row_meta = {
        submitted_at: submitted_at, status: status, reviewed_at: reviewed_at, approved_notes: approved_notes
      }

      existing = find_existing_non_draft_application(email)
      if existing
        merge_application!(existing, row_hash, row_meta)
        create_or_update_answers!(row_hash, existing)
      else
        app = build_application(row_hash, email, row_meta)
        app.save!
        create_or_update_answers!(row_hash, app)
      end

      counts[:imported] += 1
    end

    def find_existing_non_draft_application(email)
      MembershipApplication.where.not(status: 'draft')
                           .where('LOWER(email) = ?', email.downcase)
                           .order(created_at: :desc)
                           .first
    end

    def merge_application!(app, row_hash, row_meta)
      submitted_at = row_meta[:submitted_at]
      status = row_meta[:status]
      reviewed_at = row_meta[:reviewed_at]
      approved_notes = row_meta[:approved_notes]

      extras = unmapped_column_notes(row_hash)
      new_notes = compose_admin_notes(approved_notes, extras)
      attrs = {}
      attrs[:submitted_at] = submitted_at if submitted_at.present? && app.submitted_at.blank?

      if app.submitted?
        attrs[:status] = status
        if status.in?(%w[approved rejected])
          attrs[:reviewed_at] = reviewed_at
          attrs[:reviewed_by] = @imported_by if app.reviewed_by.nil?
        end
      end

      attrs[:admin_notes] = merge_note_segments(app.admin_notes, new_notes) if new_notes.present?

      app.update!(attrs) if attrs.any?
    end

    def merge_note_segments(*parts)
      parts.flatten.compact.map(&:strip).compact_blank.uniq.join("\n\n").presence
    end

    def finalize_reviewed_at(status, reviewed_at, submitted_at)
      return reviewed_at unless status.in?(%w[approved rejected])

      reviewed_at || submitted_at || Time.current
    end

    def build_application(row_hash, email, row_meta)
      status = row_meta[:status]
      submitted_at = row_meta[:submitted_at]
      reviewed_at = row_meta[:reviewed_at]
      approved_notes = row_meta[:approved_notes]

      extras = unmapped_column_notes(row_hash)
      app = MembershipApplication.new(
        email: email,
        status: status,
        submitted_at: submitted_at,
        reviewed_at: reviewed_at,
        reviewed_by: (@imported_by if status.in?(%w[approved rejected])),
        admin_notes: compose_admin_notes(approved_notes, extras)
      )
      if submitted_at
        app.created_at = submitted_at
        app.updated_at = submitted_at
      end
      app
    end

    def unmapped_column_notes(row_hash)
      extras = []
      row_hash.each do |header, value|
        next if RESERVED_HEADERS.include?(header)
        next if value.blank?
        next if @question_ids_by_label.key?(header)

        extras << "#{header}: #{value}"
      end
      extras
    end

    def compose_admin_notes(approved_notes, extras_lines)
      extra_text = extras_lines.join("\n\n").presence
      merge_note_segments(approved_notes, extra_text)
    end

    def create_or_update_answers!(row_hash, app)
      row_hash.each do |header, value|
        next if RESERVED_HEADERS.include?(header)
        next if value.blank?

        qid = @question_ids_by_label[header]
        next unless qid

        answer = app.application_answers.find_by(application_form_question_id: qid)
        v = value.to_s.strip
        if answer
          answer.update!(value: v)
        else
          ApplicationAnswer.create!(
            membership_application: app,
            application_form_question_id: qid,
            value: v
          )
        end
      end
    end

    # Returns [status, reviewed_at, notes_from_approved_cell]
    def interpret_approved(raw)
      s = raw.to_s.strip
      return ['submitted', nil, nil] if s.blank?

      return ['approved', nil, nil] if s.match?(/\A(yes|true|1|y|approved|x)\z/i)

      return ['rejected', nil, nil] if s.match?(/\A(no|false|0|n|rejected)\z/i)

      return ['rejected', nil, s[1..].to_s.strip] if s.match?(/\An/i)

      return ['approved', nil, nil] if s.match?(/\Ay/i)

      t = parse_timestamp(s)
      return ['approved', t, nil] if t

      ['submitted', nil, s]
    end

    # Parses export timestamps; uses US month/day for slash dates (e.g. 5/4/2023) so they are not read as D/M.
    # Does not pass arbitrary prose to +Time.zone.parse+ (which can treat phrases like "next month" as valid times).
    def parse_timestamp(val)
      return nil if val.blank?

      raw = val.to_s.strip

      us = raw.match(%r{\A(\d{1,2})/(\d{1,2})/(\d{4})(?:\s+(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?\z})
      if us
        return Time.zone.local(
          us[3].to_i, us[1].to_i, us[2].to_i,
          (us[4] || 0).to_i, (us[5] || 0).to_i, (us[6] || 0).to_i
        )
      end

      return Time.zone.parse(raw) if raw.match?(/\A\d{4}-\d{2}-\d{2}/)

      nil
    rescue ArgumentError, TypeError
      nil
    end
  end
end
