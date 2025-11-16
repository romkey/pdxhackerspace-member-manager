module Recharge
  class PaymentSynchronizer
    def initialize(client: Client.new, logger: Rails.logger)
      @client = client
      @logger = logger
    end

    def call
      raise ArgumentError, "Recharge integration disabled" unless RechargeConfig.enabled?

      charges = @client.charges
      now = Time.current

      RechargePayment.transaction do
        charges.each do |attrs|
          record = RechargePayment.find_or_initialize_by(recharge_id: attrs[:recharge_id])
          record.assign_attributes(
            status: attrs[:status],
            amount: attrs[:amount],
            currency: attrs[:currency],
            processed_at: attrs[:processed_at],
            charge_type: attrs[:charge_type],
            customer_email: attrs[:customer_email],
            customer_name: attrs[:customer_name],
            raw_attributes: attrs[:raw_attributes],
            last_synced_at: now
          )
          record.user = find_user(attrs[:customer_email])
          record.sheet_entry = find_sheet_entry(attrs[:customer_email])
          record.save!
        rescue ActiveRecord::RecordInvalid => e
          @logger.error("Failed to sync Recharge payment #{attrs[:recharge_id]}: #{e.message}")
        end
      end

      charges.count
    end

    private

    def find_user(email)
      normalized = normalize_email(email)
      return if normalized.blank?

      User.where("LOWER(email) = ?", normalized).first
    end

    def find_sheet_entry(email)
      normalized = normalize_email(email)
      return if normalized.blank?

      SheetEntry.where("LOWER(email) = ?", normalized).first
    end

    def normalize_email(value)
      value.to_s.strip.downcase
    end
  end
end

