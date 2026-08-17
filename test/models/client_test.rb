require "test_helper"

class ClientTest < ActiveSupport::TestCase
  test "registration signup does not require company or tel" do
    client = Client.new(
      email: "signup-blank@example.com",
      password: "password123",
      password_confirmation: "password123",
      registration_ip: "203.0.113.10"
    )

    assert client.valid?
  end
end
