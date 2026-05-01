class MembershipApplicationNagJob < ApplicationJob
  queue_as :default

  def perform
    MembershipApplications::NotifyDirectorsOfStaleApplications.call
  end
end
