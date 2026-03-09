#!/bin/bash
# ログ・一時ファイルクリーンアップスクリプト
# crontabに登録して定期実行することを推奨
#
# 登録例（毎日午前3時に実行）:
#   crontab -e
#   0 3 * * * /home/smart/webroot/okurite/bin/cleanup_logs.sh >> /home/smart/webroot/okurite/log/cleanup.log 2>&1
#
# 手動実行:
#   bash bin/cleanup_logs.sh

cd "$(dirname "$0")/.."
APP_DIR=$(pwd)

echo "$(date '+%Y-%m-%d %H:%M:%S') [cleanup] 開始: $APP_DIR"

# Railsログのローテーション（10MB超のログを圧縮・古いログを削除）
for logfile in log/production.log log/development.log log/sidekiq.log; do
  if [ -f "$logfile" ]; then
    size=$(stat -c%s "$logfile" 2>/dev/null || stat -f%z "$logfile" 2>/dev/null)
    if [ "$size" -gt 10485760 ] 2>/dev/null; then
      echo "  ログローテーション: $logfile ($(( size / 1048576 ))MB)"
      cp "$logfile" "${logfile}.$(date '+%Y%m%d')"
      : > "$logfile"
      # 7日以上前のログファイルを削除
      find log/ -name "$(basename $logfile).*" -mtime +7 -delete 2>/dev/null
    fi
  fi
done

# tmpディレクトリのクリーンアップ
if [ -d "tmp" ]; then
  find tmp/ -type f -mtime +3 -delete 2>/dev/null
  echo "  tmp/: 3日以上前のファイルを削除"
fi

# Chromeの一時ファイルをクリーンアップ
find /tmp -maxdepth 1 -name '.com.google.Chrome*' -mtime +1 -exec rm -rf {} \; 2>/dev/null
find /tmp -maxdepth 1 -name 'chrome_crashpad*' -mtime +1 -exec rm -rf {} \; 2>/dev/null
find /tmp -maxdepth 1 -name 'scoped_dir*' -mtime +1 -exec rm -rf {} \; 2>/dev/null
echo "  /tmp: Chrome一時ファイルを削除"

# ディスク使用率チェック
DISK_USAGE=$(df -h "$APP_DIR" | tail -1 | awk '{print $5}' | tr -d '%')
echo "  ディスク使用率: ${DISK_USAGE}%"

if [ "$DISK_USAGE" -gt 90 ] 2>/dev/null; then
  echo "  [警告] ディスク使用率が90%を超えています！"
  # Sidekiqを停止してこれ以上のディスク消費を防止
  sudo systemctl stop sidekiq 2>/dev/null
  echo "  [対処] Sidekiqを停止しました。ディスク容量を確認してください。"
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') [cleanup] 完了"
