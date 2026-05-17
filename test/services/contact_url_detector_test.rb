require "test_helper"

class ContactUrlDetectorTest < ActiveSupport::TestCase
  test "path keyword matching uses path boundaries" do
    detector = ContactUrlDetector.new

    assert_equal 0, detector.send(:calculate_link_score, "", "", "https://example.com/information")
    assert_operator detector.send(:calculate_link_score, "", "", "https://example.com/form"), :>, 0
    assert_operator detector.send(:calculate_link_score, "", "", "https://example.com/contact-us"), :>, 0
  end
end
