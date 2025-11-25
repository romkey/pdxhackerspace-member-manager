class AdminController < AuthenticatedController
  before_action :require_admin!
end

