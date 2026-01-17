class Column < ApplicationRecord
  mount_uploader :file, ImagesUploader
  belongs_to :parent, class_name: "Column", optional: true
  has_many :children, class_name: "Column", foreign_key: :parent_id
  # =========================
  # Scopes（よく使う絞り込み）
  # =========================
  scope :pillars, -> { where(article_type: "pillar") }
  scope :clusters, -> { where(article_type: "cluster") }

  # =========================
  # Instance methods
  # =========================

  # 親かどうか
  def pillar?
    article_type == "pillar"
  end

  # 子かどうか
  def cluster?
    article_type == "cluster"
  end

  # 子記事が上限に達しているか
  def cluster_full?
    return false unless pillar?
    return false if cluster_limit.blank?

    children.count >= cluster_limit
  end
  # FriendlyIdの設定
  extend FriendlyId
  # slugとして使うカラムを :code に固定し、FriendlyIdにそれを教える
  friendly_id :code, use: :slugged, slug_column: :code

  # ビューやヘルパーが内部で .slug を呼んだときのために定義
  #def slug
  #  code
  #end

  # --- 既存の定数 ---
  GENRE_MAPPING = {
    "cargo"        => ["cargo", "cargo"],
    "cleaning"     => ["cleaning"],
    "security"     => ["security"],
    "app"          => ["app"],
    "ai"           => ["ai"],
    "construction" => ["construction"]
  }.freeze

  CATEGORY_IMAGES = {
    'cargo'        => ['ser-cargo1.png','ser-cargo2.png','ser-cargo3.png','ser-cargo4.png'],
    'security'     => ['security1.jpg', 'security2.jpg'],
    'construction' => ['construction1.jpg', 'construction2.jpg'],
    'cleaning'     => ['cleaning1.jpg', 'cleafning2.jpg'],
    'event'        => ['event1.jpg', 'event2.jpg'],
    'logistics'    => ['logistics1.jpg', 'logistics2.jpg'],
    'app'          => ['app1.jpg', 'app2.jpg'],
    'ads'          => ['ads1.jpg', 'ads2.jpg']
  }.freeze

  def to_meta_tags
    { title: title, keyword: keyword, description: description }
  end

  def approved?
    status == "approved"
  end

  # code(slug)を更新するタイミングの制御
  def should_generate_new_friendly_id?
    code_changed? || super
  end

  before_validation :assign_random_file, on: :create

  private


def assign_random_file
  return if self.file.present?
  target_genre = self.genre.presence || self.service_type.presence
  return unless CATEGORY_IMAGES[target_genre].present?

  file_name = CATEGORY_IMAGES[target_genre].sample
  file_path = Rails.root.join("app/assets/images", file_name)

  if File.exist?(file_path)
    self.file = Rack::Test::UploadedFile.new(file_path, "image/jpeg")
  end
end
end