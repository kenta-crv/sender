require "test_helper"

class FormSendJobTest < ActiveSupport::TestCase
  test "logs replaced title and body, including a missing value" do
    customer = Customer.create!(
      company: "送信テスト株式会社",
      template_vars: {
        job_title: "SAPコンサルタント",
        company: "株式会社サンプル",
        area: ""
      }.to_json
    )
    submission = Submission.create!(
      title: "{{company}}の{{job_title}}",
      content: "{{area|全国}}で{{job_title}}を募集しています。",
      url: "https://example.test"
    )
    batch = FormSubmissionBatch.create!(
      submission: submission,
      status: "processing",
      total_count: 2,
      customer_ids: [customer.id].to_json
    )
    captured = {}
    fake_sender = Object.new
    fake_sender.define_singleton_method(:send_to_customer) { |_customer| { status: "自動送信成功", message: "stub" } }
    fake_sender.define_singleton_method(:teardown_driver) { nil }

    log = capture_log do
      with_singleton_method(FormSender, :new, ->(**kwargs) { captured.replace(kwargs); fake_sender }) do
        FormSendJob.perform_now(batch.id, customer.id)
      end
    end

    assert_includes log, "[FormSendJob] 差し込み結果:"
    assert_includes log, "株式会社サンプルのSAPコンサルタント"
    assert_includes log, "全国でSAPコンサルタントを募集しています。"
    assert_includes captured[:sender_info][:subject], "株式会社サンプルのSAPコンサルタント"
    assert_includes captured[:sender_info][:message], "全国でSAPコンサルタントを募集しています。"
    refute_includes captured[:sender_info][:message], "{{"
    assert_equal 0, Call.where(customer_id: customer.id, status: "差し込みエラー").count
  end

  test "does not send and records an interpolation error when braces remain" do
    customer = Customer.create!(
      company: "記号残り株式会社",
      template_vars: { company: "株式会社サンプル" }.to_json
    )
    submission = Submission.create!(
      title: "{{company}}様",
      content: "{{not_a_key}}へのご連絡です。",
      url: "https://example.test"
    )
    batch = FormSubmissionBatch.create!(
      submission: submission,
      status: "processing",
      total_count: 2,
      customer_ids: [customer.id].to_json
    )

    log = capture_log do
      with_singleton_method(FormSender, :new, ->(**_kwargs) { flunk "送信してはいけません" }) do
        FormSendJob.perform_now(batch.id, customer.id)
      end
    end

    assert_includes log, "{{not_a_key}}"
    assert_includes log, "未解決の差し込み"
    call = Call.find_by!(customer_id: customer.id, call_type: "form")
    assert_equal "差し込みエラー", call.status
    batch.reload
    assert_equal 1, batch.failure_count
    assert_equal 0, batch.success_count
  end

  private

  def capture_log
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original
  end

  def with_singleton_method(klass, method_name, replacement)
    original = klass.method(method_name)
    klass.define_singleton_method(method_name, &replacement)
    yield
  ensure
    klass.define_singleton_method(method_name) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end
end
