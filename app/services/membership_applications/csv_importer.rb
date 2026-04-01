# frozen_string_literal: true

require 'csv'

module MembershipApplications
  # Imports historical membership application rows from CSV exports.
  # Does not call +submit!+, +approve!+, or +reject!+ — no journal entries and no mail side effects.
  class CsvImporter
    RESERVED_HEADERS = %w[Approved Timestamp Email Address].freeze

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
      status, reviewed_at = interpret_approved(row_hash['Approved'])
      reviewed_at = finalize_reviewed_at(status, reviewed_at, submitted_at)

      app = build_application(row_hash, email:, status:, submitted_at:, reviewed_at:)
      app.save!
      create_answers!(row_hash, app)

      counts[:imported] += 1
    end

    def finalize_reviewed_at(status, reviewed_at, submitted_at)
      return reviewed_at unless status.in?(%w[approved rejected])

      reviewed_at || submitted_at || Time.current
    end

    def build_application(row_hash, email:, status:, submitted_at:, reviewed_at:)
      extras = unmapped_column_notes(row_hash)
      app = MembershipApplication.new(
        email: email,
        status: status,
        submitted_at: submitted_at,
        reviewed_at: reviewed_at,
        reviewed_by: (@imported_by if status.in?(%w[approved rejected])),
        admin_notes: extras.join("\n\n").presence
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

    def create_answers!(row_hash, app)
      row_hash.each do |header, value|
        next if RESERVED_HEADERS.include?(header)
        next if value.blank?

        qid = @question_ids_by_label[header]
        next unless qid

        ApplicationAnswer.create!(
          membership_application: app,
          application_form_question_id: qid,
          value: value.to_s.strip
        )
      end
    end

    def interpret_approved(raw)
      s = raw.to_s.strip
      return ['submitted', nil] if s.blank?

      return ['approved', nil] if s.match?(/\A(yes|true|1|y|approved|x)\z/i)

      return ['rejected', nil] if s.match?(/\A(no|false|0|n|rejected)\z/i)

      t = parse_timestamp(s)
      return ['approved', t] if t

      ['submitted', nil]
    end

    def parse_timestamp(val)
      return nil if val.blank?

      Time.zone.parse(val.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
