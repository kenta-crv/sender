# 再現テストの場面。run_replay.rb（本物）と selfcheck.rb（仕組みの確認）で共通。
# ---- 場面 ----
# 期待: plays = こちらが流す録音の順番、end = 最後の動き
SCENARIOS = [
  {
    name: '取り次ぎ → 保留音 → 担当者本人が出る',
    steps: [
      [:say, 'はい、山田商事でございます。'],
      [:wait_ours, 0.8],
      [:say, '少々お待ちくださいませ。'],
      [:wait_ours, 0.5],
      [:music, 12],
      [:say, 'お電話代わりました、総務の田中です。']
    ],
    plays: %w[greeting wait transfer], end: :transfer
  },
  {
    name: '担当者が不在',
    steps: [
      [:say, 'はい、山田商事でございます。'],
      [:wait_ours, 0.8],
      [:say, '申し訳ございません、担当の者はただいま席を外しております。']
    ],
    plays: %w[greeting 担当者不在], end: :hangup
  },
  {
    name: '営業電話を断られる',
    steps: [
      [:say, 'はい、山田商事でございます。'],
      [:wait_ours, 0.8],
      [:say, '営業のお電話でしたら、お断りしております。']
    ],
    plays: %w[greeting フロントアウト], end: :hangup
  },
  {
    name: '用件を聞かれる → 取り次ぎ → 無言の保留20秒 → 担当者',
    steps: [
      [:say, 'はい、山田商事でございます。'],
      [:wait_ours, 0.8],
      [:say, 'どういったご用件でしょうか。'],
      [:wait_ours, 0.8],
      [:say, 'かしこまりました。少々お待ちください。'],
      [:wait_ours, 0.5],
      [:silence, 20],
      [:say, 'お待たせいたしました、担当の佐藤です。']
    ],
    plays: %w[greeting purpose wait transfer], end: :transfer
  },
  {
    name: '「もしもし」と返される → 取り次ぎ',
    steps: [
      [:say, 'はい、山田商事です。'],
      [:wait_ours, 0.8],
      [:say, 'もしもし？'],
      [:wait_ours, 0.8],
      [:say, '少々お待ちください。'],
      [:wait_ours, 0.5],
      [:silence, 3]
    ],
    plays: %w[greeting smalltalk wait], end: nil
  },
  {
    name: '留守番電話',
    steps: [
      [:say, 'ただいま電話に出ることができません。ピーという発信音のあとに、お名前とご用件をお話しください。']
    ],
    plays: %w[greeting], end: :silent_hangup, plays_prefix: true
  },
  {
    name: '名乗りが遅れ、こちらの挨拶にかぶる → 挨拶を言い直す → 取り次ぎ',
    steps: [
      [:silence, 2.2],
      [:say, 'はい、お電話ありがとうございます。山田商事でございます。'],
      [:wait_ours, 0.8],
      [:say, '少々お待ちください。'],
      [:wait_ours, 0.5],
      [:silence, 2]
    ],
    plays: %w[greeting greeting wait], plays_alt: [%w[greeting wait]], end: nil
  },
  {
    name: '「ご担当の方は」に「私です」と答える（10/10 の実通話）',
    steps: [
      [:say, 'はい、山田商事です。'],
      [:wait_ours, 0.8],
      [:say, 'はい、私です。']
    ],
    plays: %w[greeting transfer], end: :transfer
  },
  {
    name: '電話に出たが、ずっと無言',
    steps: [[:silence, 1]],
    plays: %w[greeting silence_1 silence_2 callback], end: :hangup, end_wait: 30
  }
].freeze
