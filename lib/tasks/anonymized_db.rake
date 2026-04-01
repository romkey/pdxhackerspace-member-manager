# frozen_string_literal: true

namespace :db do
  desc 'Clone DB to a temp database, anonymize PII/payment IDs, dump to SQL. Does not modify the source DB. ' \
       'Usage: bin/rails db:anonymized_dump[/absolute/or/relative/path.sql] ' \
       'Default: tmp/anonymized_TIMESTAMP.sql. Use .sql.gz for gzip.'
  task :anonymized_dump, [:path] => :environment do |_t, args|
    default = Rails.root.join('tmp', "anonymized_#{Time.zone.now.strftime('%Y%m%d_%H%M%S')}.sql")
    out = args[:path].presence || default
    DatabaseAnonymizer::Export.run!(output_path: out)
  end

  desc 'Restore an anonymized SQL dump into DATABASE_URL. Refuses when Rails.env is production.'
  task :anonymized_restore, [:path] => :environment do |_t, args|
    path = args[:path]
    raise ArgumentError, 'path required: bin/rails db:anonymized_restore[path/to/dump.sql]' if path.blank?

    DatabaseAnonymizer::Restore.run!(path:)
  end
end
