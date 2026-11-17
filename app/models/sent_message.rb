class SentMessage < ApplicationRecord
  belongs_to :customer, optional: true

  # URL・メールアドレスから比較用のドメインを取り出す（www. は除く）
  def self.domain_from(value)
    return nil if value.blank?
    host = value.to_s.strip
    host = host.split('@').last if host.include?('@') && !host.include?('/')
    host = URI.parse(host.start_with?('http') ? host : "http://#{host}").host rescue nil
    host&.downcase&.sub(/\Awww\./, '')
  end
end
