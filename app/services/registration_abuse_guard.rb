# frozen_string_literal: true

class RegistrationAbuseGuard
  IP_FLAG_THRESHOLD = 3
  DOMAIN_FLAG_THRESHOLD = 5
  WINDOW = 24.hours

  def self.track!(client)
    new(client).track!
  end

  def initialize(client)
    @client = client
  end

  def track!
    flag_for_ip_abuse!
    flag_for_domain_abuse!
    track_rate_limit!
  end

  private

  attr_reader :client

  def flag_for_ip_abuse!
    ip = client.registration_ip
    return if ip.blank?

    count = Client.where(registration_ip: ip)
                  .where("created_at > ?", WINDOW.ago)
                  .count

    return if count < IP_FLAG_THRESHOLD

    client.update!(registration_flagged: true)
    Rails.logger.warn(
      "[RegistrationAbuseGuard] IP flagged client_id=#{client.id} ip=#{ip} count=#{count}"
    )
  end

  def flag_for_domain_abuse!
    domain = client.email.to_s.split("@", 2).last
    return if domain.blank?

    count = Client.where("email LIKE ?", "%@#{domain}")
                  .where("created_at > ?", WINDOW.ago)
                  .count

    return if count < DOMAIN_FLAG_THRESHOLD

    client.update!(registration_flagged: true)
    Rails.logger.warn(
      "[RegistrationAbuseGuard] Domain flagged client_id=#{client.id} domain=#{domain} count=#{count}"
    )
  end

  def track_rate_limit!
    ip = client.registration_ip
    return if ip.blank?

    cache_key = "registration_rate:#{ip}"
    count = Rails.cache.read(cache_key).to_i + 1
    Rails.cache.write(cache_key, count, expires_in: 1.hour)

    if count > 10
      client.update!(registration_flagged: true)
      Rails.logger.warn(
        "[RegistrationAbuseGuard] Rate limit flagged client_id=#{client.id} ip=#{ip} count=#{count}"
      )
    end
  end
end
