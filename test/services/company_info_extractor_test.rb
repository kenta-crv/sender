require "test_helper"

class CompanyInfoExtractorTest < ActiveSupport::TestCase
  test "clean_address removes google map label after address" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "福岡県行橋市東大橋4丁目1570-1",
      extractor.send(:clean_address, "福岡県行橋市東大橋4丁目1570-1 Google map")
    )
  end
end
