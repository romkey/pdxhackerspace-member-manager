class PaymentEventsController < ApplicationController
  include Pagy::Method

  before_action :require_admin!

  def index
    @filter = params[:event_type].presence
    scope = PaymentEvent.includes(:user).ordered
    scope = scope.by_type(@filter) if @filter.present?

    @total_count = scope.count
    @pagy, @payment_events = pagy(scope, limit: 50)
  end
end
