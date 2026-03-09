# When running tests in Docker, the final image doesn't have Node/npm (they live
# only in the multi-stage build layer). cssbundling-rails hooks css:build into
# test:prepare, which fails without npm. Set SKIP_CSS_BUILD=1 to remove that
# dependency so the already-compiled assets in the image are used as-is.
if ENV['SKIP_CSS_BUILD'].present? &&
   Rake::Task.task_defined?('test:prepare') &&
   Rake::Task.task_defined?('css:build')
  Rake::Task['test:prepare'].prerequisites.delete('css:build')
end
