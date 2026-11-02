module SapLead
  module HeadquartersArea
    PREFECTURE = /北海道|東京都|大阪府|京都府|.{2,3}県/.freeze
    # 市の次に区がある場合は区まで取る。町田市のように町で終わらせない。
    MUNICIPALITY = /.+?市.+?区|.+?[市区町村]/.freeze
    PATTERN = /\A(#{PREFECTURE}#{MUNICIPALITY})/.freeze

    def self.extract(address)
      value = address.to_s.strip.unicode_normalize(:nfkc)
      value = value.sub(/\A〒?\s*\d{3}-?\d{4}\s*/, "")
      value.match(PATTERN)&.[](1).to_s
    end
  end
end
