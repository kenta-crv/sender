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
end
