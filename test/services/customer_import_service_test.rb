require "test_helper"

class CustomerImportServiceTest < ActiveSupport::TestCase
  setup do
    @customer = Customer.create!(
      company: "テスト株式会社",
      tel: "03-1234-5678",
      address: "東京都千代田区"
    )
  end

  test "空白セルを既存値維持モードでは上書きしない" do
    csv = <<~CSV
      company,tel,address
      テスト株式会社,,大阪府大阪市
    CSV
    path = write_temp_csv(csv)

    result = CustomerImportService.new(overwrite_blank: false).call(file_path: path)

    @customer.reload
    assert_equal 1, result[:import_count]
    assert_equal "03-1234-5678", @customer.tel
    assert_equal "大阪府大阪市", @customer.address
  ensure
    File.delete(path)
  end

  test "空白セルを上書きモードでは空白に更新する" do
    csv = <<~CSV
      company,tel
      テスト株式会社,
    CSV
    path = write_temp_csv(csv)

    CustomerImportService.new(overwrite_blank: true).call(file_path: path)

    @customer.reload
    assert_equal "", @customer.tel
    assert_equal "東京都千代田区", @customer.address
  ensure
    File.delete(path)
  end

  test "CSVに列がない項目は更新しない" do
    csv = <<~CSV
      company,address
      テスト株式会社,神奈川県横浜市
    CSV
    path = write_temp_csv(csv)

    CustomerImportService.new(overwrite_blank: true).call(file_path: path)

    @customer.reload
    assert_equal "03-1234-5678", @customer.tel
    assert_equal "神奈川県横浜市", @customer.address
  ensure
    File.delete(path)
  end

  private

  def write_temp_csv(content)
    path = Rails.root.join("tmp", "customer_import_test_#{SecureRandom.uuid}.csv")
    File.write(path, content)
    path.to_s
  end
end
