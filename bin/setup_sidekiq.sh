#!/bin/bash
# Sidekiq セットアップスクリプト
# 使い方: bash bin/setup_sidekiq.sh

set -e

echo ""
echo "========================================="
echo "  Sidekiq セットアップ"
echo "========================================="
echo ""

# アプリのディレクトリに移動
cd "$(dirname "$0")/.."
APP_DIR=$(pwd)
APP_USER=$(whoami)

echo "[1/6] 環境情報"
echo "  アプリ: $APP_DIR"
echo "  ユーザー: $APP_USER"
echo ""

# Redis接続チェック
echo "[2/6] Redis接続確認..."
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

# 既存のSidekiqを停止
echo "[3/6] 既存のSidekiqプロセスを停止..."
sudo systemctl stop sidekiq 2>/dev/null || true
pkill -f sidekiq 2>/dev/null || true
sleep 2
echo "  完了"
echo ""

# サービスファイルを設置・設定
echo "[4/6] サービスファイルを設定..."
sudo cp config/sidekiq.service /etc/systemd/system/sidekiq.service
sudo sed -i "s|WorkingDirectory=.*|WorkingDirectory=$APP_DIR|" /etc/systemd/system/sidekiq.service
sudo sed -i "s|User=.*|User=$APP_USER|" /etc/systemd/system/sidekiq.service
sudo sed -i "s|Group=.*|Group=$APP_USER|" /etc/systemd/system/sidekiq.service
echo "  WorkingDirectory=$APP_DIR"
echo "  User=$APP_USER"
echo "  完了"
echo ""

# systemd登録・起動
echo "[5/6] Sidekiqを起動..."
sudo systemctl daemon-reload
sudo systemctl enable sidekiq
sudo systemctl start sidekiq
echo "  起動コマンド実行完了"
echo ""

# 起動待ち
echo "[6/6] 起動確認（10秒待機）..."
sleep 10
echo ""

# 結果表示
echo "========================================="
echo "  結果"
echo "========================================="
echo ""
echo "--- systemctl status ---"
sudo systemctl status sidekiq --no-pager 2>&1 || true
echo ""
echo "--- Sidekiqログ（直近20行）---"
journalctl -u sidekiq --no-pager -n 20 2>&1 || true
echo ""
echo "========================================="
echo "  完了"
echo "========================================="
echo ""
echo "上記の結果をご確認ください。"
echo "「active (running)」でSidekiq画面にも反映されていれば成功です。"
echo ""
echo "もし動作しない場合は、上記の出力結果をそのままお送りください。"
echo ""
