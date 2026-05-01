class AdminDashboardUrgentDigestJob < ApplicationJob
  queue_as :default

  def perform
    AdminDashboard::SendUrgentDigest.call
  end
end
