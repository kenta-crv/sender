# frozen_string_literal: true

require "test_helper"

class TrackingLinkHostTest < ActiveSupport::TestCase
  test "allows known brand hosts" do
    assert TrackingLinkHost.allowed?("j-work.jp")
    assert TrackingLinkHost.allowed?("drafity.pro")
    assert TrackingLinkHost.allowed?("okurite.pro")
  end

  test "rejects unknown hosts" do
    assert_not TrackingLinkHost.allowed?("example.com")
  end

  test "assert_allowed! raises for unknown host" do
    error = assert_raises(TrackingLinkHost::UnsupportedHostError) do
      TrackingLinkHost.assert_allowed!("example.com")
    end
    assert_match(/計測リンク非対応ホスト/, error.message)
  end
end
