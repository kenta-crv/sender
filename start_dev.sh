#!/bin/bash
# 自動発信システム 開発環境 一括起動スクリプト（macOS用）
#
# 使い方:
#   1. ターミナルで sender ディレクトリに移動
#      cd sender
#   2. 以下を実行
#      ./start_dev.sh
#
# → 4つのTerminal ウィンドウが自動で開き、それぞれ必要なサービスが起動します。
#   Redis / Sidekiq / ngrok / Rails

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

osascript <<EOF
tell application "Terminal"
    activate
    do script "echo '=== Redis ==='; redis-server"
    do script "echo '=== Sidekiq ==='; cd '$PROJECT_DIR' && bundle exec sidekiq"
    do script "echo '=== ngrok ==='; ngrok http 3000"
    do script "echo '=== Rails ==='; cd '$PROJECT_DIR' && bundle exec rails server"
end tell
EOF

echo ""
echo "✅ 4つのサービスをTerminalウィンドウで起動しました。"
echo ""
echo "停止する場合は、各ウィンドウで Ctrl+C を押すか、ウィンドウを閉じてください。"
