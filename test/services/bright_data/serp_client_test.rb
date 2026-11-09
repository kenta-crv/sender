require "test_helper"

class BrightData::SerpClientTest < ActiveSupport::TestCase
  test "authentication errors are fatal and stop the batch" do
    client = BrightData::SerpClient.new(api_key: "bad-key", zone: "serp")
    calls = 0
    yielded = []

    client.define_singleton_method(:execute_request) do |_target_url|
      calls += 1
      raise BrightData::SerpClient::AuthenticationError, "HTTP 401: Bright Data authentication failed"
    end

    results = client.batch_search(%w[first second], delay_between: 0) do |event|
      yielded << event
    end

    assert_equal 1, calls
    assert_equal 1, results.size
    assert_equal "first", results.first["query"]
    assert_equal true, results.first.dig("result", "fatal")
    assert_equal 1, yielded.size
  end

  test "sanitize_utf8 replaces invalid bytes so regex later does not raise" do
    dirty = "a\x80b".dup.force_encoding(Encoding::UTF_8)
    refute dirty.valid_encoding?

    cleaned = BrightData::SerpClient.sanitize_utf8({ "title" => dirty, "items" => [dirty] })

    assert cleaned["title"].valid_encoding?
    assert_equal "ab", cleaned["title"]
    assert cleaned["items"].first.valid_encoding?
  end

  test "a recent failure waits 15 seconds and retries once" do
    client = BrightData::SerpClient.new(api_key: "test-key", zone: "serp")
    bodies = [
      "This query recently failed and cannot be attempted at this time. Please try again later, after a minimum of 15 seconds.",
      '{"organic":[{"link":"https://example.test"}]}'
    ]
    waits = []
    client.define_singleton_method(:execute_request) { |_target_url| bodies.shift }
    client.define_singleton_method(:sleep) { |seconds| waits << seconds }

    result = client.search(query: "株式会社テスト")

    assert_equal [15], waits
    assert_equal "https://example.test", result.dig("organic", 0, "link")
    assert_nil result["error"]
  end

  test "a recent failure is not retried more than once" do
    client = BrightData::SerpClient.new(api_key: "test-key", zone: "serp")
    calls = 0
    waits = []
    client.define_singleton_method(:execute_request) do |_target_url|
      calls += 1
      "直前に失敗したため再試行してください"
    end
    client.define_singleton_method(:sleep) { |seconds| waits << seconds }

    result = client.search(query: "株式会社テスト")

    assert_equal 2, calls
    assert_equal [15], waits
    assert_equal "recent_failure", result["error"]
  end

  test "batch search waits the given interval between companies" do
    client = BrightData::SerpClient.new(api_key: "test-key", zone: "serp")
    waits = []
    client.define_singleton_method(:execute_request) { |_target_url| '{"organic":[]}' }
    client.define_singleton_method(:sleep) { |seconds| waits << seconds }

    client.batch_search(%w[one two three], delay_between: 15)

    assert_equal [15, 15], waits
  end
end
