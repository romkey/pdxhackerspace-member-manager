require 'sidekiq/web'
require_relative '../../lib/sidekiq_web_auth'

# Protect Sidekiq web UI with session-based authentication
Sidekiq::Web.use SidekiqWebAuth::Middleware

