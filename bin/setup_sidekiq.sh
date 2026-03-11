#!/bin/bash
# Sidekiq セットアップスクリプト（okurite専用）
# 使い方: bash bin/setup_sidekiq.sh
#
# 旧sidekiq.serviceを削除し、sidekiq-okurite.serviceとして登録します。
# これにより他アプリ（tcarepro等）のSidekiqと競合しません。

set -e

SERVICE_NAME="sidekiq-okurite"

echo ""
echo "========================================="
echo "  Sidekiq セットアップ（okurite専用）"
echo "========================================="
echo ""

# アプリのディレクトリに移動
cd "$(dirname "$0")/.."
APP_DIR=$(pwd)
APP_USER=$(whoami)

echo "[1/7] 環境情報"
echo "  アプリ: $APP_DIR"
echo "  ユーザー: $APP_USER"
echo "  サービス名: $SERVICE_NAME"
echo ""

# Redis接続チェック
echo "[2/7] Redis接続確認..."
if command -v redis-cli > /dev/null 2>&1; then
  if redis-cli ping > /dev/null 2>&1; then
    echo "  OK: Redisに接続できました"
  else
    echo "  NG: Redisに接続できません"
    echo "  → 以下を試してください: sudo systemctl start redis"
    exit 1
  fi
else
  echo "  確認スキップ（redis-cliが見つかりません）"
fi
echo ""

# 旧サービス（sidekiq.service）を停止・無効化（削除はしない）
echo "[3/7] 旧サービス（sidekiq.service）を整理..."
if systemctl list-unit-files | grep -q '^sidekiq.service'; then
  sudo systemctl stop sidekiq 2>/dev/null || true
  sudo systemctl disable sidekiq 2>/dev/null || true
  echo "  旧sidekiq.serviceを停止・無効化しました"
  echo "  ※ファイルは残してあります。tcareproで使用する場合は"
  echo "    WorkingDirectoryをtcareproに書き換えてご利用ください。"
else
  echo "  旧sidekiq.serviceは存在しません（スキップ）"
fi
echo ""

# okurite用Sidekiqを停止
echo "[4/7] 既存のokurite用Sidekiqを停止..."
sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true
sleep 2
echo "  完了"
echo ""

# サービスファイルを設置・設定
echo "[5/7] サービスファイルを設定..."
sudo cp config/sidekiq-okurite.service "/etc/systemd/system/${SERVICE_NAME}.service"
sudo sed -i "s|WorkingDirectory=.*|WorkingDirectory=$APP_DIR|" "/etc/systemd/system/${SERVICE_NAME}.service"
sudo sed -i "s|User=.*|User=$APP_USER|" "/etc/systemd/system/${SERVICE_NAME}.service"
sudo sed -i "s|Group=.*|Group=$APP_USER|" "/etc/systemd/system/${SERVICE_NAME}.service"
echo "  WorkingDirectory=$APP_DIR"
echo "  User=$APP_USER"
echo "  完了"
echo ""

# systemd登録・起動
echo "[6/7] Sidekiqを起動..."
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"
echo "  起動コマンド実行完了"
echo ""

# 起動待ち
echo "[7/7] 起動確認（10秒待機）..."
sleep 10
echo ""

# 結果表示
echo "========================================="
echo "  結果"
echo "========================================="
echo ""
echo "--- systemctl status $SERVICE_NAME ---"
sudo systemctl status "$SERVICE_NAME" --no-pager 2>&1 || true
echo ""
echo "--- Sidekiqログ（直近20行）---"
journalctl -u "$SERVICE_NAME" --no-pager -n 20 2>&1 || true
echo ""
echo "========================================="
echo "  完了"
echo "========================================="
echo ""
echo "上記の結果をご確認ください。"
echo "「active (running)」でSidekiq画面にも反映されていれば成功です。"
echo ""
echo "※ tcareproのSidekiqは別途 sidekiq-tcarepro.service として"
echo "  tcarepro側で設定してください。"
echo ""
echo "もし動作しない場合は、上記の出力結果をそのままお送りください。"
echo ""
