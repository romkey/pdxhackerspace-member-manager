class AuthenticatedController < ApplicationController
  before_action :require_authenticated_user!
end
