# SPDX-FileCopyrightText: 2025 John Romkey
#
# SPDX-License-Identifier: CC0-1.0

class RfidWebhookService
  REDIS_KEY_PREFIX = 'rfid_webhook:'
  EXPIRATION_TIME = 5.minutes

  def self.store(rfid_code, pin_code, reader_id = nil, reader_name = nil)
    key = redis_key(rfid_code)
    data = {
      rfid: rfid_code,
      pin: pin_code,
      reader_id: reader_id,
      reader_name: reader_name,
      created_at: Time.current.to_i
    }.to_json

    redis.setex(key, EXPIRATION_TIME.to_i, data)
    rfid_code
  end

  def self.retrieve(rfid_code)
    key = redis_key(rfid_code)
    data = redis.get(key)
    return nil if data.nil?

    JSON.parse(data).symbolize_keys
  rescue JSON::ParserError
    nil
  end

  def self.verify_and_consume(rfid_code, pin_code)
    data = retrieve(rfid_code)
    return false if data.nil?

    if data[:pin] == pin_code.to_s
      key = redis_key(rfid_code)
      redis.del(key)
      true
    else
      false
    end
  end

  def self.delete(rfid_code)
    key = redis_key(rfid_code)
    redis.del(key)
  end

  def self.find_recent(since_time)
    # Scan all keys with our prefix
    keys = redis.keys("#{REDIS_KEY_PREFIX}*")
    
    # Find the most recent webhook created after since_time
    most_recent = nil
    most_recent_time = nil
    
    keys.each do |key|
      data = redis.get(key)
      next if data.nil?
      
      begin
        parsed = JSON.parse(data).symbolize_keys
        created_at = Time.at(parsed[:created_at])
        
        # Only consider webhooks created after the session started
        if created_at >= since_time
          if most_recent_time.nil? || created_at > most_recent_time
            most_recent = parsed
            most_recent_time = created_at
          end
        end
      rescue JSON::ParserError, ArgumentError
        next
      end
    end
    
    most_recent
  end

  private

  def self.redis_key(rfid_code)
    "#{REDIS_KEY_PREFIX}#{rfid_code.to_s.downcase.strip}"
  end

  def self.redis
    @redis ||= Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
  end
end

