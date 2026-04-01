# frozen_string_literal: true

require 'digest'
require 'English'
require 'openssl'
require 'open3'
require 'shellwords'
require 'tmpdir'
require 'zlib'
require 'bcrypt'

# Scrubs PII and processor identifiers from a PostgreSQL clone for safe local/staging use.
# Run only against a disposable database (see db:anonymized_dump).
module DatabaseAnonymizer
  class Error < StandardError; end

  class ProductionRestoreForbidden < Error; end

  class InvalidDumpError < Error; end

  ANON_DOMAIN = 'anon.invalid'

  DUMP_MARKER = 'membermanager:anonymized_export v1'

  FIRST_NAMES = %w[
    Jordan Riley Morgan Casey Taylor Avery Cameron Sage Quinn Reese Drew Blair Parker Skyler
    Devon Rowan Sydney Alex Peyton Kendall Dakota Finley River Skyler Jamie Morgan
  ].freeze

  LAST_NAMES = %w[
    Mercer Holloway Okonkwo Nakamura Lindstrom Okafor Delgado Fontaine Kowalczyk Petrov
    Yamamoto Benavides Okoro Thatcher Morales Reeves Park Singh Ibrahim Carver Bowen
  ].freeze

  module_function

  class Export
    def self.run!(output_path:)
      new(output_path:).run!
    end

    def initialize(output_path:)
      @output_path = Pathname.new(output_path)
    end

    def run!
      source_url = ENV.fetch('DATABASE_URL')
      parts = self.class.connection_parts(source_url)
      temp_db = "#{parts[:db]}_anon_#{Process.pid}_#{SecureRandom.hex(4)}"
      temp_url = self.class.build_url(source_url, database: temp_db)
      env = self.class.pg_env(parts)

      begin
        Dir.mktmpdir('member_manager_anon') do |workdir|
          raw_dump = File.join(workdir, 'raw.sql')

          Rails.logger.info('[anonymized_db] Creating temporary database...')
          self.class.run_shell(env, 'createdb', '-h', parts[:host], '-p', parts[:port].to_s,
                               '-U', parts[:user], temp_db)

          Rails.logger.info('[anonymized_db] Copying schema and data (pg_dump → new DB)...')
          self.class.run_shell(env, 'pg_dump', '-Fp', '--no-owner', '--no-acl', '-d', source_url,
                               '-f', raw_dump)
          self.class.run_shell(env, 'psql', '-v', 'ON_ERROR_STOP=1', '-d', temp_url, '-f', raw_dump)

          Rails.logger.info('[anonymized_db] Anonymizing clone...')
          prior_url = ENV.fetch('DATABASE_URL')
          begin
            ENV['DATABASE_URL'] = temp_url
            ActiveRecord::Base.establish_connection
            ActiveRecord::Base.connection_pool.disconnect!
            ActiveRecord::Base.establish_connection
            Scrubber.run!
          ensure
            ENV['DATABASE_URL'] = prior_url
            ActiveRecord::Base.establish_connection
          end

          @output_path.parent.mkpath
          final_sql = File.join(workdir, 'final.sql')
          self.class.run_shell(env, 'pg_dump', '-Fp', '--no-owner', '--no-acl', '-d', temp_url,
                               '-f', final_sql)

          header = "-- #{DatabaseAnonymizer::DUMP_MARKER}\n"
          Rails.logger.info("[anonymized_db] Writing #{@output_path}...")
          if @output_path.to_s.end_with?('.gz')
            Zlib::GzipWriter.open(@output_path) do |gz|
              gz.write(header)
              File.open(final_sql, 'r') { |f| IO.copy_stream(f, gz) }
            end
          else
            File.open(@output_path, 'w') do |out|
              out.write(header)
              IO.copy_stream(File.open(final_sql, 'r'), out)
            end
          end
        end
      ensure
        Rails.logger.info('[anonymized_db] Dropping temporary database (if still present)...')
        system(env, 'dropdb', '-h', parts[:host], '-p', parts[:port].to_s,
               '-U', parts[:user], '--if-exists', temp_db)
      end

      Rails.logger.info("[anonymized_db] Done: #{File.size(@output_path)} bytes")
      @output_path.to_s
    end

    def self.connection_parts(database_url)
      uri = URI.parse(database_url)
      {
        host: uri.host || 'localhost',
        port: uri.port || 5432,
        user: URI.decode_www_form_component(uri.user || 'postgres'),
        password: uri.password ? URI.decode_www_form_component(uri.password) : nil,
        db: uri.path.delete_prefix('/')
      }
    end

    def self.build_url(source_url, database:)
      u = URI.parse(source_url)
      u.path = "/#{database}"
      u.to_s
    end

    def self.pg_env(parts)
      env = ENV.to_h.transform_keys(&:to_s)
      env['PGPASSWORD'] = parts[:password] if parts[:password].present?
      env
    end

    def self.run_shell(env_hash, *cmd)
      success = system(env_hash, *cmd)
      raise "Command failed (exit #{$CHILD_STATUS.exitstatus}): #{cmd.join(' ')}" unless success
    end
  end

  class Restore
    def self.refuse_if_production!
      return unless Rails.env.production?

      raise ProductionRestoreForbidden,
            'Anonymized DB restore is not allowed when Rails.env is production.'
    end

    def self.dump_has_marker?(path)
      if path.to_s.end_with?('.gz')
        Zlib::GzipReader.open(path) { |z| z.read(512).to_s.include?(DUMP_MARKER) }
      else
        File.read(path, 512).to_s.include?(DUMP_MARKER)
      end
    end

    def self.run!(path:)
      refuse_if_production!

      path = Pathname.new(path)
      raise "File not found: #{path}" unless path.file?

      unless dump_has_marker?(path)
        raise InvalidDumpError,
              "#{DUMP_MARKER} header missing. Use dumps from bin/rails db:anonymized_dump only."
      end

      url = ENV.fetch('DATABASE_URL')
      parts = Export.connection_parts(url)
      env = Export.pg_env(parts)

      Rails.logger.info('[anonymized_db] Restoring anonymized dump into current DATABASE_URL target...')
      if path.to_s.end_with?('.gz')
        restore_gzip_to_psql(env, path, url)
      else
        Export.run_shell(env, 'psql', '-v', 'ON_ERROR_STOP=1', '-d', url, '-f', path.to_s)
      end
      Rails.logger.info('[anonymized_db] Restore complete.')
    end

    def self.restore_gzip_to_psql(env, path, url)
      script = [
        'set -euo pipefail; gzip -dc ',
        Shellwords.escape(path.to_s),
        ' | psql -v ON_ERROR_STOP=1 ',
        Shellwords.escape(url)
      ].join
      _stdout, stderr, status = Open3.capture3(env, 'bash', '-c', script)
      return if status.success?

      raise Error, "Restore failed: #{stderr.presence || 'unknown error'}"
    end
  end

  class Scrubber
    def self.run!(conn = ActiveRecord::Base.connection)
      new(conn).run!
    end

    def initialize(conn)
      @conn = conn
      @bcrypt = BCrypt::Password.create('Anonymized1!', cost: 4)
    end

    def run!
      @conn.transaction do
        build_email_map!
        apply_email_updates!
        scrub_users!
        scrub_authentik_and_slack!
        scrub_sheet_and_applications!
        scrub_messages_and_mail!
        scrub_payment_tables!
        scrub_tokens_and_ids!
        scrub_misc_text!
        scrub_arrays_and_json!
      end
    end

    private

    def quote(str)
      @conn.quote(str)
    end

    def select_rows(sql)
      @conn.exec_query(sql)
    end

    def build_email_map!
      sql = <<~SQL.squish
        SELECT DISTINCT LOWER(TRIM(e)) AS email FROM (
          SELECT email AS e FROM users WHERE email IS NOT NULL AND TRIM(email) <> ''
          UNION SELECT UNNEST(extra_emails) AS e FROM users
            WHERE extra_emails IS NOT NULL AND cardinality(extra_emails) > 0
          UNION SELECT email AS e FROM authentik_users WHERE email IS NOT NULL AND TRIM(email) <> ''
          UNION SELECT email AS e FROM application_verifications WHERE TRIM(email) <> ''
          UNION SELECT email AS e FROM membership_applications WHERE TRIM(email) <> ''
          UNION SELECT email AS e FROM invitations WHERE TRIM(email) <> ''
          UNION SELECT email AS e FROM local_accounts WHERE TRIM(email) <> ''
          UNION SELECT "to" AS e FROM queued_mails WHERE TRIM("to") <> ''
          UNION SELECT email AS e FROM slack_users WHERE email IS NOT NULL AND TRIM(email) <> ''
          UNION SELECT email AS e FROM sheet_entries WHERE email IS NOT NULL AND TRIM(email) <> ''
          UNION SELECT email AS e FROM kofi_payments WHERE email IS NOT NULL AND TRIM(email) <> ''
          UNION SELECT payer_email AS e FROM paypal_payments
            WHERE payer_email IS NOT NULL AND TRIM(payer_email) <> ''
          UNION SELECT customer_email AS e FROM recharge_payments
            WHERE customer_email IS NOT NULL AND TRIM(customer_email) <> ''
        ) x WHERE e IS NOT NULL AND TRIM(e) <> ''
      SQL
      rows = @conn.select_values(sql)
      @email_map = rows.index_with { |e| DatabaseAnonymizer.fake_email_for_string(e) }
    end

    def apply_email_updates!
      update_email_column('users', 'email')
      update_email_column('authentik_users', 'email')
      update_email_column('application_verifications', 'email')
      update_email_column('membership_applications', 'email')
      update_email_column('invitations', 'email')
      update_email_column('local_accounts', 'email')
      update_email_column('slack_users', 'email')
      update_email_column('sheet_entries', 'email')
      update_email_column('kofi_payments', 'email')
      update_email_column('paypal_payments', 'payer_email')
      update_email_column('recharge_payments', 'customer_email')
      update_queued_mails_to!
    end

    def update_email_column(table, column)
      return if @email_map.empty?

      @email_map.each_slice(200) do |slice|
        values = slice.map { |old, newe| "(#{quote(old)}, #{quote(newe)})" }.join(', ')
        sql = <<~SQL.squish
          UPDATE #{table} t SET #{column} = m.ne
          FROM (VALUES #{values}) AS m(oe, ne)
          WHERE LOWER(TRIM(t.#{column})) = m.oe
        SQL
        @conn.execute(sql)
      end
    end

    def update_queued_mails_to!
      select_rows('SELECT id, "to" FROM queued_mails').each do |row|
        raw = row['to'].to_s
        next if raw.strip.empty?

        replacement = if raw.match?(/\A[^@\s]+@[^@\s]+\z/)
                        @email_map[raw.downcase.strip] || DatabaseAnonymizer.fake_email_for_string(raw)
                      else
                        DatabaseAnonymizer.fake_email_for_string(raw)
                      end
        @conn.execute("UPDATE queued_mails SET \"to\" = #{quote(replacement)} WHERE id = #{row['id'].to_i}")
      end
    end

    def scrub_users!
      select_rows('SELECT id FROM users').each do |row|
        id = row['id'].to_i
        uname = "member#{id}"
        names = DatabaseAnonymizer.fake_profile_names(id)
        @conn.execute(<<~SQL.squish)
          UPDATE users SET
            full_name = #{quote(names[:full])},
            greeting_name = #{quote(names[:greeting])},
            sign_name = #{quote(names[:sign])},
            username = #{quote(uname)},
            slack_handle = #{quote("mem_#{id}")},
            slack_id = #{quote("U#{DatabaseAnonymizer.fake_token_hex('slack_uid', id, 8)}")},
            notes = #{redacted_text},
            bio = #{redacted_text},
            avatar = NULL,
            pronouns = NULL,
            authentik_id = #{quote("ak-#{DatabaseAnonymizer.fake_token_hex('authentik', id, 24)}")},
            paypal_account_id = #{quote("PP-#{DatabaseAnonymizer.fake_token_hex('paypal', id, 12)}")},
            recharge_customer_id = #{quote("rc_#{DatabaseAnonymizer.fake_token_hex('recharge', id, 16)}")},
            login_token = #{quote(DatabaseAnonymizer.fake_token_hex('login', id, 32))},
            login_token_expires_at = NULL,
            authentik_attributes = '{}'::jsonb,
            authentik_dirty = false
          WHERE id = #{id}
        SQL
      end
      scrub_user_arrays!
    end

    def scrub_user_arrays!
      User.find_each do |u|
        ex = u.extra_emails
        al = u.aliases
        next if ex.blank? && al.blank?

        new_ex =
          if ex.present?
            ex.each_with_index.map { |e, i| DatabaseAnonymizer.fake_email_for_string("#{u.id}-ex-#{i}|#{e}") }
          else
            ex
          end
        new_al =
          if al.present?
            al.each_with_index.map { |a, i| DatabaseAnonymizer.fake_aliases_segment("#{u.id}|#{i}|#{a}") }
          else
            al
          end

        u.update_columns(extra_emails: new_ex, aliases: new_al)
      end
    end

    def scrub_authentik_and_slack!
      select_rows('SELECT id FROM authentik_users').each do |row|
        id = row['id'].to_i
        @conn.execute(<<~SQL.squish)
          UPDATE authentik_users SET
            authentik_id = #{quote("ak-row-#{DatabaseAnonymizer.fake_token_hex('authentik_row', id, 20)}")},
            full_name = #{quote(DatabaseAnonymizer.fake_person_name("authentik|#{id}"))},
            username = #{quote("user_ak_#{id}")},
            raw_attributes = '{}'::jsonb
          WHERE id = #{id}
        SQL
      end

      select_rows('SELECT id FROM slack_users').each do |row|
        id = row['id'].to_i
        base = DatabaseAnonymizer.fake_person_name("slack|#{id}")
        @conn.execute(<<~SQL.squish)
          UPDATE slack_users SET
            slack_id = #{quote("U#{DatabaseAnonymizer.fake_token_hex('slack_id', id, 8)}")},
            team_id = #{quote("T#{DatabaseAnonymizer.fake_token_hex('team', id, 8)}")},
            display_name = #{quote(base.split.first)},
            real_name = #{quote(base)},
            username = #{quote("slack_#{id}")},
            phone = NULL,
            title = NULL,
            pronouns = NULL,
            raw_attributes = '{}'::jsonb
          WHERE id = #{id}
        SQL
      end
    end

    def scrub_sheet_and_applications!
      select_rows('SELECT id FROM sheet_entries').each do |row|
        id = row['id'].to_i
        @conn.execute(<<~SQL.squish)
          UPDATE sheet_entries SET
            name = #{quote(DatabaseAnonymizer.fake_person_name("sheet|#{id}"))},
            alias_name = #{quote("alias-#{DatabaseAnonymizer.fake_token_hex('alias', id, 8)}")},
            paypal_name = #{quote(DatabaseAnonymizer.fake_person_name("paypal_sheet|#{id}"))},
            notes = #{redacted_text},
            rfid = #{quote(DatabaseAnonymizer.fake_token_hex('rfid_sheet', id, 12))},
            twitter = #{quote("@t_#{DatabaseAnonymizer.fake_token_hex('tw', id, 6)}")},
            raw_attributes = '{}'::jsonb
          WHERE id = #{id}
        SQL
      end

      select_rows('SELECT id FROM application_answers').each do |row|
        @conn.execute("UPDATE application_answers SET value = #{redacted_text} WHERE id = #{row['id'].to_i}")
      end

      select_rows('SELECT id FROM membership_applications').each do |row|
        id = row['id'].to_i
        @conn.execute(<<~SQL.squish)
          UPDATE membership_applications SET
            token = #{quote(DatabaseAnonymizer.fake_token_hex('mapp', id, 32))},
            admin_notes = #{redacted_text}
          WHERE id = #{id}
        SQL
      end

      select_rows('SELECT id FROM application_verifications').each do |row|
        id = row['id'].to_i
        @conn.execute(<<~SQL.squish)
          UPDATE application_verifications SET
            token = #{quote(DatabaseAnonymizer.fake_token_hex('aver', id, 32))}
          WHERE id = #{id}
        SQL
      end

      select_rows('SELECT id FROM invitations').each do |row|
        id = row['id'].to_i
        tok = quote(DatabaseAnonymizer.fake_token_hex('inv', id, 32))
        @conn.execute("UPDATE invitations SET token = #{tok} WHERE id = #{id}")
      end
    end

    def scrub_messages_and_mail!
      r = redacted_text
      subj = quote('Message subject redacted')
      @conn.execute("UPDATE messages SET body = #{r}, subject = #{subj}")

      select_rows('SELECT id FROM queued_mails').each do |row|
        id = row['id'].to_i
        @conn.execute(<<~SQL.squish)
          UPDATE queued_mails SET
            body_html = #{redacted_text},
            body_text = #{redacted_text},
            subject = #{quote("Mail #{id}")},
            mailer_args = '{}'::jsonb,
            last_error = NULL
          WHERE id = #{id}
        SQL
      end

      @conn.execute('UPDATE mail_log_entries SET details = NULL')
    end

    def scrub_payment_tables!
      select_rows('SELECT id, amount FROM paypal_payments').each do |row|
        id = row['id'].to_i
        amt = DatabaseAnonymizer.fake_amount_sql(id, row['amount'])
        @conn.execute(<<~SQL.squish)
          UPDATE paypal_payments SET
            amount = #{amt},
            paypal_id = #{quote("PAYPAL-#{DatabaseAnonymizer.fake_token_hex('pp_tx', id, 20)}")},
            payer_id = #{quote("PAYER-#{DatabaseAnonymizer.fake_token_hex('pp_payer', id, 16)}")},
            payer_name = #{quote(DatabaseAnonymizer.fake_person_name("payer|#{id}"))},
            raw_attributes = '{}'::jsonb
          WHERE id = #{id}
        SQL
      end

      select_rows('SELECT id, amount FROM recharge_payments').each do |row|
        id = row['id'].to_i
        amt = DatabaseAnonymizer.fake_amount_sql(id, row['amount'])
        @conn.execute(<<~SQL.squish)
          UPDATE recharge_payments SET
            amount = #{amt},
            recharge_id = #{quote("rch_#{DatabaseAnonymizer.fake_token_hex('rch', id, 20)}")},
            customer_id = #{quote("cust_#{DatabaseAnonymizer.fake_token_hex('cust', id, 12)}")},
            customer_name = #{quote(DatabaseAnonymizer.fake_person_name("rch_name|#{id}"))},
            raw_attributes = '{}'::jsonb
          WHERE id = #{id}
        SQL
      end

      select_rows('SELECT id, amount FROM kofi_payments').each do |row|
        id = row['id'].to_i
        amt = DatabaseAnonymizer.fake_amount_sql(id, row['amount'])
        @conn.execute(<<~SQL.squish)
          UPDATE kofi_payments SET
            amount = #{amt},
            kofi_transaction_id = #{quote("kofi-#{DatabaseAnonymizer.fake_token_hex('kofi', id, 18)}")},
            message_id = #{quote("msg-#{DatabaseAnonymizer.fake_token_hex('kofi_msg', id, 12)}")},
            from_name = #{quote(DatabaseAnonymizer.fake_person_name("kofi_from|#{id}"))},
            message = #{redacted_text},
            url = #{quote("https://ko-fi.com/s/#{DatabaseAnonymizer.fake_token_hex('kofi_url', id, 8)}")},
            raw_attributes = '{}'::jsonb,
            shop_items = '[]'::jsonb
          WHERE id = #{id}
        SQL
      end

      select_rows('SELECT id, amount FROM cash_payments').each do |row|
        id = row['id'].to_i
        amt = DatabaseAnonymizer.fake_amount_sql(id, row['amount'])
        @conn.execute(<<~SQL.squish)
          UPDATE cash_payments SET
            amount = #{amt},
            notes = #{redacted_text}
          WHERE id = #{id}
        SQL
      end

      select_rows('SELECT id, amount, external_id FROM payment_events').each do |row|
        id = row['id'].to_i
        amt = DatabaseAnonymizer.fake_amount_sql(id, row['amount'])
        ext =
          if row['external_id'].present?
            quote("ext-#{DatabaseAnonymizer.fake_token_hex('pext', id, 16)}")
          else
            'NULL'
          end
        @conn.execute(<<~SQL.squish)
          UPDATE payment_events SET
            amount = #{amt},
            external_id = #{ext},
            details = #{redacted_text}
          WHERE id = #{id}
        SQL
      end
    end

    def scrub_tokens_and_ids!
      select_rows('SELECT id FROM access_controllers').each do |row|
        id = row['id'].to_i
        @conn.execute(<<~SQL.squish)
          UPDATE access_controllers SET
            access_token = #{quote(DatabaseAnonymizer.fake_token_hex('actoken', id, 32))},
            hostname = #{quote("host-#{id}.lan")},
            description = #{redacted_text}
          WHERE id = #{id}
        SQL
      end

      select_rows('SELECT id FROM rfid_readers').each do |row|
        id = row['id'].to_i
        k = quote(DatabaseAnonymizer.fake_token_hex('rfidr', id, 16))
        @conn.execute("UPDATE rfid_readers SET key = #{k} WHERE id = #{id}")
      end

      select_rows('SELECT id FROM rfids').each do |row|
        id = row['id'].to_i
        @conn.execute(<<~SQL.squish)
          UPDATE rfids SET
            rfid = #{quote(DatabaseAnonymizer.fake_token_hex('rfidtag', id, 20))},
            notes = #{redacted_text}
          WHERE id = #{id}
        SQL
      end

      select_rows('SELECT id FROM application_groups').each do |row|
        id = row['id'].to_i
        @conn.execute(<<~SQL.squish)
          UPDATE application_groups SET
            authentik_group_id = #{quote("ag-#{DatabaseAnonymizer.fake_token_hex('ag', id, 12)}")},
            authentik_policy_id = #{quote("pol-#{DatabaseAnonymizer.fake_token_hex('pol', id, 12)}")}
          WHERE id = #{id}
        SQL
      end

      select_rows('SELECT id FROM active_storage_blobs').each do |row|
        id = row['id'].to_i
        @conn.execute(<<~SQL.squish)
          UPDATE active_storage_blobs SET
            key = #{quote("anon/blob-#{id}")},
            filename = #{quote("file-#{id}.bin")},
            checksum = #{quote(DatabaseAnonymizer.fake_token_hex('chk', id, 16))}
          WHERE id = #{id}
        SQL
      end
    end

    def scrub_misc_text!
      @conn.execute('UPDATE access_logs SET name = NULL, raw_text = NULL')
      d = redacted_text
      @conn.execute(<<~SQL.squish)
        UPDATE incident_reports SET
          description = #{d},
          resolution = #{d},
          subject = #{quote('Incident subject redacted')},
          other_type_explanation = NULL
      SQL
      @conn.execute(<<~SQL.squish)
        UPDATE parking_notices SET
          notes = NULL,
          description = NULL,
          location = #{quote('—')},
          location_detail = NULL
      SQL
      @conn.execute('UPDATE trainings SET notes = NULL')
      select_rows('SELECT id FROM journals').each do |row|
        @conn.execute("UPDATE journals SET changes_json = '{}'::jsonb WHERE id = #{row['id'].to_i}")
      end
      @conn.execute("UPDATE incident_report_links SET url = #{quote('https://example.invalid/report-link')}")
      @conn.execute("UPDATE user_links SET url = #{quote('https://example.invalid/profile-link')}")

      @conn.execute('UPDATE member_sources SET notes = NULL, last_error_message = NULL')
      @conn.execute(
        'UPDATE payment_processors SET notes = NULL, payment_link = NULL, webhook_url = NULL, ' \
        'last_error_message = NULL'
      )

      select_rows('SELECT id FROM local_accounts').each do |row|
        id = row['id'].to_i
        @conn.execute(<<~SQL.squish)
          UPDATE local_accounts SET
            full_name = #{quote(DatabaseAnonymizer.fake_person_name("local|#{id}"))},
            password_digest = #{quote(@bcrypt.to_s)}
          WHERE id = #{id}
        SQL
      end
    end

    def scrub_arrays_and_json!
      @conn.execute('UPDATE membership_plans SET payment_link = NULL, paypal_transaction_subject = NULL')
    end

    def redacted_text
      quote('[redacted]')
    end
  end

  def fake_email_for_string(raw)
    h = Digest::SHA256.hexdigest("email|#{raw.to_s.downcase.strip}")[0..11]
    "#{h}@#{ANON_DOMAIN}"
  end

  def fake_person_name(seed)
    crc = Zlib.crc32(seed.to_s)
    "#{FIRST_NAMES[crc % FIRST_NAMES.length]} #{LAST_NAMES[(crc / FIRST_NAMES.size) % LAST_NAMES.length]}"
  end

  def fake_profile_names(user_id)
    base = fake_person_name("profile|#{user_id}")
    { full: base, greeting: base.split.first, sign: base.split.last }
  end

  def fake_aliases_segment(key)
    "alias-#{Digest::SHA256.hexdigest(key.to_s)[0..7]}"
  end

  def fake_token_hex(salt, id, bytes = 16)
    OpenSSL::HMAC.hexdigest('SHA256', salt.to_s, id.to_s)[0, bytes * 2]
  end

  def fake_amount_sql(row_id, original)
    return 'NULL' if original.nil?

    base = Zlib.crc32("amt|#{row_id}") % 50_000
    val = (base + (row_id % 97)) / 100.0
    format('%.2f', val)
  end
end
