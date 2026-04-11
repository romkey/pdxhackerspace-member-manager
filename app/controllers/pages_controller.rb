class PagesController < ApplicationController
  before_action :require_authenticated_user!, only: %i[help help_faq help_admin_faq]
  before_action :require_admin!, only: [:help_admin_faq]

  def apply
    # Public page - no authentication required
    return unless MembershipSetting.use_builtin_membership_application?

    redirect_to apply_new_path
  end

  def help
    @help_title = 'General'
    @help_fragment_key = 'help_general'
    @help_content = TextFragment.content_for('help_general').presence || TextFragment.content_for('navbar_help')
  end

  def help_faq
    @help_title = 'FAQ'
    @help_fragment_key = 'help_faq'
    @help_content = TextFragment.content_for('help_faq')
    render :help
  end

  def help_admin_faq
    @help_title = 'Admin FAQ'
    @help_fragment_key = 'help_admin_faq'
    @help_content = TextFragment.content_for('help_admin_faq')
    render :help
  end
end
