# frozen_string_literal: true

# app/services/industry_classifier.rb
#
# SERPで取得した情報をもとに業種を判定し Customer#business に保存する。
# 判定ソース: company名 + SERPタイトル のキーワードマッチのみ。
# customer.industry は一切使わない。

class IndustryClassifier
  # 業種リスト: [表示名, キーワード配列] の順。上から順に判定し最初にマッチした業種を採用。
  INDUSTRY_LIST = [
    ["IT・Web・システム",     %w[IT Web システム ソフトウェア アプリ 開発 プログラム インターネット クラウド ネットワーク セキュリティ DX デジタル 情報]],
    ["広告・マーケティング",  %w[広告 マーケティング 宣伝 PR プロモーション SEO SNS]],
    ["コンサルティング",      %w[コンサルティング コンサル 経営支援 戦略 マネジメント BPO]],
    ["人材・派遣",            %w[人材 派遣 採用 求人 転職 ヘッドハンティング リクルート]],
    ["不動産",                %w[不動産 賃貸 売買 仲介 マンション アパート 住宅]],
    ["建設・土木",            %w[建設 工事 施工 土木 建築 設備 内装 リフォーム 塗装 解体]],
    ["製造・メーカー",        %w[製造 メーカー 工場 生産 加工 機械 電機 電子 化学 金属]],
    ["物流・運送",            %w[物流 運送 配送 宅配 倉庫 輸送 トラック 配達 ロジスティクス]],
    ["飲食・フード",          %w[飲食 レストラン カフェ 居酒屋 食品 フード 料理 外食]],
    ["医療・介護・福祉",      %w[医療 病院 クリニック 介護 福祉 ケア 薬局 歯科 看護 リハビリ]],
    ["教育・研修",            %w[教育 学校 塾 スクール 研修 学習 予備校 保育]],
    ["小売・EC",              %w[小売 販売 ショップ 通販 EC オンラインショップ]],
    ["金融・保険",            %w[金融 銀行 証券 保険 投資 ファンド リース]],
    ["美容・エステ",          %w[美容 ヘアサロン 美容室 エステ ネイル マッサージ 整体]],
    ["その他サービス",        %w[サービス 代行 清掃 警備 修理 メンテナンス]],
  ].freeze

  FALLBACK = "その他・不明"

  # @param company [String]  企業名
  # @param title   [String]  SERPタイトル
  # @return [String]
  def self.classify(company: nil, title: nil)
    texts = [company, title].compact.map { |t|
      t.to_s.tr("Ａ-Ｚａ-ｚ０-９", "A-Za-z0-9")
    }.join(" ")

    return FALLBACK if texts.blank?

    INDUSTRY_LIST.each do |label, keywords|
      return label if keywords.any? { |kw| texts.include?(kw) }
    end

    FALLBACK
  end

  # Customer レコードに分類結果を保存する。
  # business が既に入っている場合は上書きしない。
  # 判定ソースは company名 と SERPタイトルのみ。customer.industry は使わない。
  def self.classify_and_save!(customer, company_data = {})
    return if customer.business.present?

    label = classify(
      company: company_data[:company].presence || customer.company.presence,
      title:   company_data[:title].presence
    )

    customer.update_columns(business: label, updated_at: Time.current)
  rescue => e
    Rails.logger.warn("[IndustryClassifier] error for customer##{customer.id}: #{e.message}")
  end
end