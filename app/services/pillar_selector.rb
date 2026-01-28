class PillarSelector
  def self.select_available_pillar(genre = nil)
    # 1. ジャンル指定があれば、まずはそのジャンル内で探す
    if genre.present?
      pillar = find_pillar(genre)
      return pillar if pillar
      puts "--- [#{genre}] では空きpillarが見つからなかったため、全ジャンルから再探索 ---"
    end

    # 2. ジャンル問わず再探索
    find_pillar(nil)
  end

  private

  def self.find_pillar(genre_name)
    scope = Column.pillars.where(parent_id: nil) # ← 親は必ず parent_id nil のみ許可

    scope = scope.where(genre: genre_name.to_s) if genre_name.present?

    pillar = scope
      .left_joins(:children)
      .group("columns.id")
      .having("COUNT(children_columns.id) < COALESCE(columns.cluster_limit, 999)")
      .order(Arel.sql("RANDOM()"))
      .first

    if pillar
      puts "✅ 使用するpillar: id=#{pillar.id}, genre=#{pillar.genre}, children=#{pillar.children.count}"
    end

    pillar
  end
end
