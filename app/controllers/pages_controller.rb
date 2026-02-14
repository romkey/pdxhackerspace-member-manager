class PagesController < ApplicationController
  before_action :require_admin!, only: [:help]

  def apply
    # Public page - no authentication required
  end

  def help
    @help_content = TextFragment.content_for('admin_help')
  end
end
