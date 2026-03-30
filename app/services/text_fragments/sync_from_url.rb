require 'faraday/follow_redirects'

module TextFragments
  class SyncFromUrl
    class Error < StandardError; end

    # Optional block yields the normalized fetch URL; return an object responding to
    # +success?+, +status+, and +body+ (like a Faraday response). Used in tests.
    def self.call(fragment, &block)
      new(fragment, fetch: block).call
    end

    def initialize(fragment, fetch: nil)
      @fragment = fragment
      @fetch = fetch
    end

    def call
      url = @fragment.source_url.to_s.strip
      raise Error, 'No source URL is configured.' if url.blank?

      fetch_url = SourceUrlNormalizer.call(url)
      validate_fetch_uri!(fetch_url)

      response =
        if @fetch
          @fetch.call(fetch_url)
        else
          http_get(fetch_url)
        end

      raise Error, "Could not download (#{response.status}): #{fetch_url}" unless response.success?

      body = response.body.to_s
      body = body.force_encoding(Encoding::UTF_8)
      body = body.encode(Encoding::UTF_8, invalid: :replace, undef: :replace) unless body.valid_encoding?

      @fragment.update!(content: body)
      @fragment
    end

    private

    def http_get(fetch_url)
      http_client.get(fetch_url)
    rescue Faraday::Error => e
      raise Error, "Download failed: #{e.message}"
    end

    def validate_fetch_uri!(url_string)
      uri = URI.parse(url_string)
      raise Error, 'Source URL must be http or https.' unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      raise Error, 'Source URL must include a host.' if uri.host.blank?
      raise Error, 'Only http and https schemes are allowed.' unless %w[http https].include?(uri.scheme)
    rescue URI::InvalidURIError => e
      raise Error, "Invalid URL: #{e.message}"
    end

    def http_client
      @http_client ||= Faraday.new do |f|
        f.response :follow_redirects
        f.adapter Faraday.default_adapter
        f.options.timeout = 30
        f.options.open_timeout = 10
        f.headers['User-Agent'] = 'MemberManager TextFragmentSync/1.0'
      end
    end
  end
end
