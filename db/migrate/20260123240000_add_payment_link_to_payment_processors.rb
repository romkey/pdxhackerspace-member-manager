class AddPaymentLinkToPaymentProcessors < ActiveRecord::Migration[7.1]
  def change
    add_column :payment_processors, :payment_link, :string
  end
end
