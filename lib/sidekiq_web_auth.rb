module SidekiqWebAuth
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      request = Rack::Request.new(env)

      # Get session from the request
      session_key = Rails.application.config.session_options[:key] || '_member_manager_session'
      cookie = request.cookies[session_key]

      user_id = nil
      if cookie
        # Decode session to check for user_id
        session_store = ActionDispatch::Session::CookieStore.new(Rails.application)
        session = session_store.send(:load_session, request)
        user_id = session['user_id'] || session[:user_id]
      end

      return [302, { 'Location' => '/login', 'Content-Type' => 'text/html' }, []] if user_id.blank?

      @app.call(env)
    end
  end
end
