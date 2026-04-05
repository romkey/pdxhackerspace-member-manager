# frozen_string_literal: true

# Public multi-step application flow (email verification required).
# Include +MembershipApplicationWizard+ first, then +MembershipApplicationWizard::Actions+
# on the controller so Actions' +before_action+ filters apply to the controller class.
module MembershipApplicationWizard
  extend ActiveSupport::Concern

  include Helpers
  include Verification
end
