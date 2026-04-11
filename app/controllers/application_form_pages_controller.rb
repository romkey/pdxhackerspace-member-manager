class ApplicationFormPagesController < AdminController
  before_action :set_page, only: %i[edit update destroy]

  def index
    @pages = ApplicationFormPage.ordered.includes(:questions)
    @membership_setting = MembershipSetting.instance
  end

  def new
    @page = ApplicationFormPage.new(position: (ApplicationFormPage.maximum(:position) || 0) + 1)
  end

  def edit; end

  def create
    @page = ApplicationFormPage.new(page_params)
    if @page.save
      redirect_to application_form_pages_path, notice: 'Page added successfully.'
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @page.update(page_params)
      redirect_to application_form_pages_path, notice: 'Page updated successfully.'
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @page.destroy!
    redirect_to application_form_pages_path, notice: 'Page removed.'
  end

  def update_application_flow
    setting = MembershipSetting.instance
    raw = params[:use_builtin_membership_application]
    if raw.nil?
      redirect_to application_form_pages_path, alert: 'Choose how applicants should apply.'
      return
    end

    if setting.update(use_builtin_membership_application: ActiveModel::Type::Boolean.new.cast(raw))
      redirect_to application_form_pages_path, notice: 'Application flow updated.'
    else
      redirect_to application_form_pages_path, alert: setting.errors.full_messages.to_sentence
    end
  end

  private

  def set_page
    @page = ApplicationFormPage.find(params[:id])
  end

  def page_params
    params.expect(application_form_page: %i[title description position])
  end
end
