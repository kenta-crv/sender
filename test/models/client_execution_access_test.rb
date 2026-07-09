require "test_helper"

class ClientExecutionAccessTest < ActiveSupport::TestCase
  test "payment_method_registered? is true when stripe ids are present" do
    client = Client.new(
      stripe_customer_id: "cus_test",
      stripe_payment_method_id: "pm_test"
    )

    assert client.payment_method_registered?
  end

  test "payment_method_registered? is false without payment method" do
    client = Client.new(stripe_customer_id: "cus_test")

    assert_not client.payment_method_registered?
  end
end
