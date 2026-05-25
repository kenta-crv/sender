class AddStripeColumns < ActiveRecord::Migration[6.1]
  def change
    add_column :clients,:stripe_customer_id,:string
    add_column :subscriptions,:stripe_subscription_id,:string
    add_column :payments,:stripe_payment_intent_id,:string
    add_index :clients,:stripe_customer_id,unique: true
    add_index :subscriptions,:stripe_subscription_id,unique: true
    add_index :payments,:stripe_payment_intent_id,unique: true
  end
end
