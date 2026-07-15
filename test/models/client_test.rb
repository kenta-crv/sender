require "test_helper"

class ClientTest < ActiveSupport::TestCase
  test "registration signup requires company and tel" do
    client = Client.new(
      email: "signup-blank@example.com",
      password: "password123",
      password_confirmation: "password123",
      registration_ip: "203.0.113.10"
    )

    assert_not client.valid?
    assert_equal ["を入力してください"], client.errors[:company]
    assert_equal ["を入力してください"], client.errors[:tel]
  end

  test "registration signup requires a corporate title in company name" do
    client = Client.new(
      email: "signup-company@example.com",
      password: "password123",
      password_confirmation: "password123",
      registration_ip: "203.0.113.10",
      company: "オクライト",
      tel: "09012345678"
    )

    assert_not client.valid?
    assert_equal ["は法人敬称（株式会社、有限会社、合同会社など）を含めてください"], client.errors[:company]
  end

  test "registration signup requires digits only for tel" do
    client = Client.new(
      email: "signup-tel@example.com",
      password: "password123",
      password_confirmation: "password123",
      registration_ip: "203.0.113.10",
      company: "株式会社オクライト",
      tel: "090-1234-5678"
    )

    assert_not client.valid?
    assert_equal ["は数字のみで入力してください"], client.errors[:tel]
  end
end
