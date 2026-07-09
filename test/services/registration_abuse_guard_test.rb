require "test_helper"

class RegistrationAbuseGuardTest < ActiveSupport::TestCase
  test "flags client when multiple registrations share the same ip" do
    2.times do |i|
      Client.create!(
        email: "ip-test-#{i}@example.com",
        password: "password123",
        registration_ip: "203.0.113.10",
        confirmed_at: Time.current
      )
    end

    third = Client.create!(
      email: "ip-test-3@example.com",
      password: "password123",
      registration_ip: "203.0.113.10",
      confirmed_at: Time.current
    )

    RegistrationAbuseGuard.track!(third)

    assert third.reload.registration_flagged?
  end

  test "does not flag client for isolated registration" do
    client = Client.create!(
      email: "isolated@example.com",
      password: "password123",
      registration_ip: "198.51.100.20",
      confirmed_at: Time.current
    )

    RegistrationAbuseGuard.track!(client)

    assert_not client.reload.registration_flagged?
  end
end
