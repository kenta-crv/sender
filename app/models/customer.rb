class Customer < ApplicationRecord
  has_many :calls
  has_one :last_call, -> { order(created_at: :desc) }, class_name: 'Call'

  scope :between_created_at, ->(from, to){
    where(created_at: from..to).where.not(tel: nil)
  }
  scope :between_called_at, ->(from, to){
    where(created_at: from..to)
  }


  scope :ltec_calls_count, ->(count){
    filter_ids = joins(:calls).group("calls.customer_id").having('count(*) <= ?',count).count.keys
    where(id: filter_ids)
  }
    # Ransack で検索可能な関連を明示
  def self.ransackable_associations(auth_object = nil)
    %w[calls last_call]
  end

  # Ransack で検索可能なカラムを明示（必要に応じて）
  def self.ransackable_attributes(auth_object = nil)
    %w[
      company      # 会社名
      name         # 代表者
      tel          # 電話番号1
      address      # 住所
      mobile       # 携帯番号
      industry     # 業種
      email        # メール
      url          # URL
      business     # 業種詳細
      genre        # 職種
      contact_form # 問い合わせフォーム
      remarks      # 備考
      fobbiden
      contact_url  # お問い合わせフォームURL
      created_at
      updated_at
      id
    ]
  end
end
