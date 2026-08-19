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

  test "from_omniauth sign_up creates a new client" do
    auth = omniauth_hash(email: "new-oauth@example.com", uid: "uid-new")

    assert_difference "Client.count", 1 do
      client = Client.from_omniauth(auth, intent: "sign_up")
      assert_equal "new-oauth@example.com", client.email
      assert_equal "google_oauth2", client.provider
      assert_equal "uid-new", client.uid
    end
  end

  test "from_omniauth sign_up rejects an existing account" do
    Client.create!(
      email: "existing-oauth@example.com",
      password: "password123",
      provider: "google_oauth2",
      uid: "uid-existing"
    )
    auth = omniauth_hash(email: "existing-oauth@example.com", uid: "uid-existing")

    error = assert_raises(ArgumentError) do
      Client.from_omniauth(auth, intent: "sign_up")
    end
    assert_match(/既に登録/, error.message)
  end

  test "from_omniauth sign_in finds an existing account and does not create" do
    existing = Client.create!(
      email: "login-oauth@example.com",
      password: "password123",
      provider: "google_oauth2",
      uid: "uid-login"
    )
    auth = omniauth_hash(email: "login-oauth@example.com", uid: "uid-login")

    assert_no_difference "Client.count" do
      client = Client.from_omniauth(auth, intent: "sign_in")
      assert_equal existing.id, client.id
    end
  end

  test "from_omniauth sign_in rejects a missing account" do
    auth = omniauth_hash(email: "missing-oauth@example.com", uid: "uid-missing")

    error = assert_raises(ArgumentError) do
      Client.from_omniauth(auth, intent: "sign_in")
    end
    assert_match(/未登録/, error.message)
  end

  private

  def omniauth_hash(email:, uid:, provider: "google_oauth2")
    OmniAuth::AuthHash.new(
      provider: provider,
      uid: uid,
      info: { email: email, name: "OAuth User" }
    )
  end
end
