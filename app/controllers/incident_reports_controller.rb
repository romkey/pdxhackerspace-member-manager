class IncidentReportsController < AdminController
  before_action :set_incident_report, only: [:show, :edit, :update, :destroy]

  def index
    @incident_reports = IncidentReport.includes(:reporter, :involved_members).ordered
    @incident_count = @incident_reports.count
  end

  def show
  end

  def new
    @incident_report = IncidentReport.new(incident_date: Date.current)
    @users = User.ordered_by_display_name
  end

  def create
    @incident_report = IncidentReport.new(incident_report_params)
    @incident_report.reporter = current_user

    if @incident_report.save
      # Create journal entries for all involved members
      @incident_report.create_journal_entries_for_members(
        @incident_report.involved_member_ids,
        actor: current_user
      )
      redirect_to incident_report_path(@incident_report), notice: 'Incident report created successfully.'
    else
      @users = User.ordered_by_display_name
      flash.now[:alert] = 'Unable to create incident report.'
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @users = User.ordered_by_display_name
  end

  def update
    # Track which members were involved before the update
    previous_member_ids = @incident_report.involved_member_ids.dup

    if @incident_report.update(incident_report_params)
      # Create journal entries only for newly added members
      new_member_ids = @incident_report.involved_member_ids - previous_member_ids
      if new_member_ids.any?
        @incident_report.create_journal_entries_for_members(
          new_member_ids,
          actor: current_user
        )
      end
      redirect_to incident_report_path(@incident_report), notice: 'Incident report updated successfully.'
    else
      @users = User.ordered_by_display_name
      flash.now[:alert] = 'Unable to update incident report.'
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @incident_report.destroy!
    redirect_to incident_reports_path, notice: 'Incident report deleted.'
  end

  private

  def set_incident_report
    @incident_report = IncidentReport.includes(:reporter, :involved_members).find(params[:id])
  end

  def incident_report_params
    params.require(:incident_report).permit(
      :incident_date,
      :subject,
      :incident_type,
      :other_type_explanation,
      :description,
      photos: [],
      involved_member_ids: []
    )
  end
end
