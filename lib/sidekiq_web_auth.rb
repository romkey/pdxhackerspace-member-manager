module SidekiqWebAuth
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      # Manually decode Rails session cookie
      request = Rack::Request.new(env)
      session_key = Rails.application.config.session_options[:key] || '_member_manager_session'
      cookie_value = request.cookies[session_key]
      
      user_id = nil
      if cookie_value
        begin
          # Use ActionDispatch::Session::CookieStore to decode the session
          # We need to create a request that has the cookie in the right format
          session_store = ActionDispatch::Session::CookieStore.new(Rails.application)
          
          # Create an env hash with cookies properly set
          session_env = env.dup
          # Ensure HTTP_COOKIE includes our session cookie
          existing_cookies = session_env['HTTP_COOKIE'] || ''
          session_env['HTTP_COOKIE'] = existing_cookies.empty? ? 
            "#{session_key}=#{cookie_value}" : 
            "#{existing_cookies}; #{session_key}=#{cookie_value}"
          
          # Create a request object that can access cookies
          # Use Rack::Request which doesn't require cookie_jar
          session_request = Rack::Request.new(session_env)
          
          # Use the session store's load_session method
          # We need to pass it a request that has cookie_jar, so we'll use a workaround
          # Create a minimal ActionDispatch::Request by ensuring cookie middleware has run
          session_data = session_store.send(:load_session, session_request)
          user_id = session_data['user_id'] || session_data[:user_id] if session_data
        rescue NoMethodError, ArgumentError => e
          # If we can't decode (e.g., cookie_jar not available), try manual decryption
          begin
            # Fallback: manually decrypt using Rails' encryption
            secret_key_base = Rails.application.secret_key_base
            key_generator = ActiveSupport::KeyGenerator.new(secret_key_base, iterations: 1000)
            secret = key_generator.generate_key('encrypted cookie')
            sign_secret = key_generator.generate_key('signed encrypted cookie')
            
            encryptor = ActiveSupport::MessageEncryptor.new([secret, sign_secret], serializer: JSON)
            session_data = encryptor.decrypt_and_verify(cookie_value)
            user_id = session_data['user_id'] || session_data[:user_id]
          rescue => decrypt_error
            Rails.logger.debug("Sidekiq auth: Failed to decode session: #{decrypt_error.message}")
            user_id = nil
          end
        rescue => e
          Rails.logger.debug("Sidekiq auth: Failed to decode session: #{e.message}")
          user_id = nil
        end
      end

      if user_id.blank?
        [302, { 'Location' => '/login', 'Content-Type' => 'text/html' }, []]
      else
        @app.call(env)
      end
    end
  end
end
