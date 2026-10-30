require "test_helper"

class FormTemplateRendererTest < ActiveSupport::TestCase
  test "replaces known keys and uses per-template fallback text when a value is missing" do
    rendered = FormTemplateRenderer.render(
      title: "{{company}}様",
      content: "{{job_title|求人}}のご担当者様。勤務地は{{area}}です。",
      template_vars: { company: "株式会社サンプル", job_title: "" }.to_json
    )

    assert_nil rendered.error
    assert_equal "株式会社サンプル様", rendered.title
    assert_equal "求人のご担当者様。勤務地はです。", rendered.content
    assert rendered.logged
  end

  test "reports an error when unresolved braces remain" do
    rendered = FormTemplateRenderer.render(
      title: "ご連絡",
      content: "{{company}}の{{unknown}}について",
      template_vars: { company: "株式会社サンプル" }.to_json
    )

    assert_equal "株式会社サンプルの{{unknown}}について", rendered.content
    assert_match "本文", rendered.error
  end
end
