class ReportsController < AuthenticatedController
  def index
    @membership_status_unknown = User.where(membership_status: 'unknown', active: true).ordered_by_display_name
    @payment_type_unknown = User.where(payment_type: 'unknown', active: true).ordered_by_display_name
    @dues_status_unknown = User.where(dues_status: 'unknown', active: true).ordered_by_display_name
    @dues_status_lapsed = User.where(dues_status: 'lapsed', active: true).ordered_by_display_name
  end
end
