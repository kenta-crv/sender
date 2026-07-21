# app/models/lp_definition.rb
module LpDefinition
  MAP = {
    'okurite'      => 'Okurite',
    'sales'        => 'Ri-Plus',
    'columns'      => 'お役立ち記事',
    'cargo'        => '軽貨物',
    'security'     => '警備業',
    'construction' => '建設業',
    'cleaning'     => '清掃業',
    'event'        => 'イベント',
    'logistics'    => '物流業',
    'app'          => 'テレアポ代行',
    'ads'          => '広告CPA改善'
  }.freeze

  def self.label(key)
    MAP[key.to_s]
  end
end
