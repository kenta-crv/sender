#!/bin/bash
# Sidekiq セットアップスクリプト（okurite + tcarepro）
# 使い方: bash bin/setup_sidekiq.sh
#
# 旧sidekiq.serviceを廃止し、アプリごとに専用サービスとして登録します。
#   - sidekiq-okurite.service（okurite用）
#   - sidekiq-tcarepro.service（tcarepro用）

set -e

SERVICE_NAME="sidekiq-okurite"

echo ""
echo "========================================="
echo "  Sidekiq セットアップ（okurite + tcarepro）"
echo "========================================="
echo ""

# アプリのディレクトリに移動
cd "$(dirname "$0")/.."
APP_DIR=$(pwd)
APP_USER=$(whoami)

echo "[1/10] 環境情報"
echo "  アプリ: $APP_DIR"
echo "  ユーザー: $APP_USER"
echo "  サービス名: $SERVICE_NAME"
echo ""

# Redis接続チェック
echo "[2/10] Redis接続確認..."
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
echo "[3/10] 旧サービス（sidekiq.service）を整理..."
if systemctl list-unit-files | grep -q '^sidekiq.service'; then
  sudo systemctl stop sidekiq 2>/dev/null || true
  sudo systemctl disable sidekiq 2>/dev/null || true
  echo "  旧sidekiq.serviceを停止・無効化しました"
else
  echo "  旧sidekiq.serviceは存在しません（スキップ）"
fi
echo ""

# okurite用Sidekiqを停止
echo "[4/10] 既存のokurite用Sidekiqを停止..."
sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true
sleep 2
echo "  完了"
echo ""

# サービスファイルを設置・設定
echo "[5/10] okurite用サービスファイルを設定..."
sudo cp config/sidekiq-okurite.service "/etc/systemd/system/${SERVICE_NAME}.service"
sudo sed -i "s|WorkingDirectory=.*|WorkingDirectory=$APP_DIR|" "/etc/systemd/system/${SERVICE_NAME}.service"
sudo sed -i "s|User=.*|User=$APP_USER|" "/etc/systemd/system/${SERVICE_NAME}.service"
sudo sed -i "s|Group=.*|Group=$APP_USER|" "/etc/systemd/system/${SERVICE_NAME}.service"
echo "  WorkingDirectory=$APP_DIR"
echo "  User=$APP_USER"
echo "  完了"
echo ""

# systemd登録・起動
echo "[6/10] okurite用Sidekiqを起動..."
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"
echo "  起動コマンド実行完了"
echo ""

# 起動待ち
echo "[7/10] okurite起動確認（10秒待機）..."
sleep 10
echo ""

# tcarepro用サービスを設定
TCAREPRO_SERVICE="sidekiq-tcarepro"
TCAREPRO_DIR="/home/smart/tcarepro"

echo "[8/10] tcarepro用Sidekiqを設定..."
if [ -d "$TCAREPRO_DIR" ]; then
  sudo systemctl stop "$TCAREPRO_SERVICE" 2>/dev/null || true
  sudo cp config/sidekiq-tcarepro.service "/etc/systemd/system/${TCAREPRO_SERVICE}.service"
  sudo sed -i "s|WorkingDirectory=.*|WorkingDirectory=$TCAREPRO_DIR|" "/etc/systemd/system/${TCAREPRO_SERVICE}.service"
  sudo sed -i "s|User=.*|User=$APP_USER|" "/etc/systemd/system/${TCAREPRO_SERVICE}.service"
  sudo sed -i "s|Group=.*|Group=$APP_USER|" "/etc/systemd/system/${TCAREPRO_SERVICE}.service"
  echo "  WorkingDirectory=$TCAREPRO_DIR"
  echo "  完了"
else
  echo "  $TCAREPRO_DIR が見つかりません（スキップ）"
fi
echo ""

echo "[9/10] tcarepro用Sidekiqを起動..."
if [ -d "$TCAREPRO_DIR" ]; then
  sudo systemctl daemon-reload
  sudo systemctl enable "$TCAREPRO_SERVICE"
  sudo systemctl start "$TCAREPRO_SERVICE"
  echo "  起動コマンド実行完了"
else
  echo "  スキップ"
fi
echo ""

echo "[10/10] 起動確認（10秒待機）..."
sleep 10
echo ""

# 結果表示
echo "========================================="
echo "  結果"
echo "========================================="
echo ""
echo "--- sidekiq-okurite ---"
sudo systemctl status "$SERVICE_NAME" --no-pager 2>&1 || true
echo ""
if [ -d "$TCAREPRO_DIR" ]; then
  echo "--- sidekiq-tcarepro ---"
  sudo systemctl status "$TCAREPRO_SERVICE" --no-pager 2>&1 || true
  echo ""
fi
echo "========================================="
echo "  完了"
echo "========================================="
echo ""
echo "上記の結果をご確認ください。"
echo "「active (running)」と表示されていれば成功です。"
echo ""
echo "もし動作しない場合は、上記の出力結果をそのままお送りください。"
echo ""
