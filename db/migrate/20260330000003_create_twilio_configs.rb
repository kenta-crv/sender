class CreateTwilioConfigs < ActiveRecord::Migration[6.1]
  def change
    create_table :twilio_configs do |t|
      t.text :greeting_text, default: "お電話ありがとうございます。株式会社テストでございます。ご担当者様はいらっしゃいますでしょうか。"
      t.text :absent_text, default: "承知いたしました。不在とのことですね。改めてお電話させていただきます。失礼いたします。"
      t.text :inquiry_text, default: "ありがとうございます。本日は新しいサービスのご案内でお電話いたしました。"
      t.text :rejection_text, default: "承知いたしました。お時間いただきありがとうございました。失礼いたします。"
      t.text :transfer_text, default: "オペレーターにおつなぎいたします。"
      t.text :wait_text
      t.string :operator_number
      t.string :from_number
      t.integer :no_answer_timeout, default: 7
      t.integer :speech_timeout, default: 3
      t.integer :gather_timeout, default: 5
      t.string :voice_language, default: "ja-JP"
      t.string :voice_name, default: "Polly.Mizuki"
      t.text :speech_hints, default: "不在にしております,いません,おりません,いないです,留守にしております,出かけております,席を外しております,ご用件は,結構です,必要ありません,間に合っております,いらないです,大丈夫です,お電話代わりました,お電話かわりました,電話代わりました,少々お待ちください,お待ちください,お待たせしました,担当の"
      t.boolean :recording_enabled, default: true
      t.integer :recording_min_duration, default: 60
      t.boolean :active, default: true

      t.timestamps
    end
  end
end
