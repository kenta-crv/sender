require "test_helper"

class SapScheduleTest < ActiveSupport::TestCase
  test "saturday resolve job registers only after resolve finishes" do
    source = Rails.root.join("app/jobs/sap_lead_resolve_job.rb").read
    assert_operator source.index("SapLead::Resolver"), :<, source.index("SapLead::Registrar")
  end

  test "cron times stay in JST" do
    source = Rails.root.join("config/initializers/sidekiq_cron.rb").read
    assert_includes source, "'0 2 * * * Asia/Tokyo'"
    assert_includes source, "'0 4 * * 6 Asia/Tokyo'"
    assert_includes source, "'0 4 * * 0 Asia/Tokyo'"
    assert_includes source, "'0 9 * * 1 Asia/Tokyo'"
    assert_includes source, "'0 22 * * 5 Asia/Tokyo'"
  end

  test "sap cron next time is calculated in Tokyo" do
    scrape = Fugit.parse_cronish("0 2 * * * Asia/Tokyo")
    nxt = scrape.next_time(Time.utc(2026, 11, 2, 16, 59, 0)).to_t.getlocal("+09:00")
    assert_equal 2026, nxt.year
    assert_equal 11, nxt.month
    assert_equal 3, nxt.day
    assert_equal 2, nxt.hour
    assert_equal 0, nxt.min

    saturday = Fugit.parse_cronish("0 4 * * 6 Asia/Tokyo")
    sat = saturday.next_time(Time.utc(2026, 11, 6, 18, 0, 0)).to_t.getlocal("+09:00")
    assert_equal 6, sat.wday
    assert_equal 4, sat.hour
    assert_equal 0, sat.min

    expectations = {
      "SAP Kyujinbox scrape - daily at 2:00" => [Time.utc(2026, 11, 3, 18, 0, 0), 2, 0],
      "SAP lead resolve and register - Saturday at 4:00" => [Time.utc(2026, 11, 7, 0, 0, 0), 4, 0],
      "SAP sunday url and form detect - Sunday at 4:00" => [Time.utc(2026, 11, 8, 0, 0, 0), 4, 0],
      "SAP weekly send - Monday at 9:00" => [Time.utc(2026, 11, 9, 1, 0, 0), 9, 0],
      "SAP weekly report - Friday at 22:00" => [Time.utc(2026, 11, 6, 13, 30, 0), 22, 0]
    }
    expectations.each do |name, (moment, hour, minute)|
      job = Sidekiq::Cron::Job.find(name)
      assert_includes job.cron, "Asia/Tokyo"
      local = job.send(:last_time, moment).getlocal("+09:00")
      assert_equal hour, local.hour, name
      assert_equal minute, local.min, name
    end
  end
end
