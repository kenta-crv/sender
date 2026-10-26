class AddDialContextAndResponseBanks < ActiveRecord::Migration[6.1]
  SAMPLES = {
    'greeting' => [
      'お電話ありがとうございます。',
      'お世話になっております。お電話口をお借りします。',
      '突然のお電話、失礼いたします。'
    ],
    'purpose' => [
      '本日はご案内でお電話しました。続きをお聞きいただけますか。',
      '簡単に概要だけお伝えしたいのですが、少々お時間よろしいでしょうか。',
      'ご担当の方へご案内があり、お電話いたしました。続けてもよろしいでしょうか。'
    ],
    'wait' => [
      '承知しました。そのままお待ちします。',
      'かしこまりました。お待ちしております。',
      'はい、少々お待ちくださいませ。'
    ],
    'smalltalk' => [
      'お世話になっております。恐れ入りますが、本日のご案内を続けてもよろしいでしょうか。',
      'ありがとうございます。それでは本日の件、短くご説明してもよろしいでしょうか。',
      'お忙しいところ恐れ入ります。改めまして、ご案内の続きをお聞きいただけますか。'
    ],
    'clarify' => [
      '恐れ入ります、少々聞き取りづらかったです。もう一度、ご都合だけお聞かせいただけますか。',
      'すみません、音声が少し途切れてしまいました。もう一度お願いできますでしょうか。'
    ],
    'clarify_alt' => [
      '申し訳ございません、うまく聞き取れませんでした。差し支えなければもう一度お願いできますか。',
      '恐れ入ります。もう一度だけ、ご回答をお願いできますでしょうか。'
    ],
    'clarify_simple' => [
      'はい、またはいいえだけでも結構です。続けてご案内してよろしいでしょうか。',
      '簡単で構いません。続ける場合ははい、難しい場合はいいえ、とお答えください。'
    ],
    'callback' => [
      'それでは、改めてお電話させていただきます。失礼いたします。',
      'おそれいります。改めましてご連絡いたしますので、本日は失礼いたします。'
    ]
  }.freeze

  def up
    add_column :calls, :conversation_context, :text
    add_column :dial_scripts, :response_banks, :text

    say_with_time 'seed sample response banks' do
      DialScript.reset_column_information
      DialScript.find_each do |script|
        banks = {}
        SAMPLES.each do |key, lines|
          legacy = script_legacy_text(script, key)
          banks[key] = ([legacy] + lines).compact.map(&:to_s).map(&:strip).reject(&:blank?).uniq
        end
        script.update_columns(response_banks: JSON.generate(banks))
      end
    end
  end

  def down
    remove_column :dial_scripts, :response_banks
    remove_column :calls, :conversation_context
  end

  def script_legacy_text(script, key)
    case key
    when 'greeting' then script.greeting_text
    when 'purpose' then script.purpose_text
    when 'wait' then script.wait_text
    when 'smalltalk' then script.try(:smalltalk_text)
    when 'clarify' then script.try(:clarify_text)
    when 'clarify_alt' then script.try(:clarify_alt_text)
    when 'clarify_simple' then script.try(:clarify_simple_text)
    when 'callback' then script.try(:callback_text)
    else nil
    end
  end
end
