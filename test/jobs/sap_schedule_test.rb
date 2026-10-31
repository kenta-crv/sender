require "test_helper"

class SapScheduleTest < ActiveSupport::TestCase
  test "saturday resolve job registers only after resolve finishes" do
    source = Rails.root.join("app/jobs/sap_lead_resolve_job.rb").read
    assert_operator source.index("SapLead::Resolver"), :<, source.index("SapLead::Registrar")
  end

  test "cron times stay in JST" do
    source = Rails.root.join("config/initializers/sidekiq_cron.rb").read
    assert_includes source, "'47 2 * * *'"
    assert_includes source, "'17 3 * * 6'"
    assert_includes source, "'17 3 * * 0'"
    assert_includes source, "'13 9 * * 1'"
    assert_includes source, "'43 21 * * 5'"
    refute_includes source, "timezone"
  end
end
