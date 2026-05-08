#!/bin/bash
# ログ・一時ファイル・Chrome残骸クリーンアップスクリプト
# crontabに登録して定期実行することを推奨
#
# 登録例（毎時実行）:
#   crontab -e
#   0 * * * * /home/smart/webroot/okurite/bin/cleanup_logs.sh >> /home/smart/webroot/okurite/log/cleanup.log 2>&1
#
# 手動実行:
#   bash bin/cleanup_logs.sh

cd "$(dirname "$0")/.."
APP_DIR=$(pwd)

echo "$(date '+%Y-%m-%d %H:%M:%S') [cleanup] 開始: $APP_DIR"

# ローテーション対象: 既知の3ログ + log/配下で500MB超のログを動的に追加
ROTATE_TARGETS="log/production.log log/development.log log/sidekiq.log"
if [ -d "log" ]; then
  while IFS= read -r big_log; do
    [ -n "$big_log" ] && ROTATE_TARGETS="$ROTATE_TARGETS $big_log"
  done < <(find log -maxdepth 1 -type f -size +500M 2>/dev/null)
fi

for logfile in $(echo $ROTATE_TARGETS | tr ' ' '\n' | sort -u); do
  if [ -f "$logfile" ]; then
    size=$(stat -c%s "$logfile" 2>/dev/null || stat -f%z "$logfile" 2>/dev/null)
    if [ "$size" -gt 10485760 ] 2>/dev/null; then
      echo "  ログローテーション: $logfile ($(( size / 1048576 ))MB)"
      cp "$logfile" "${logfile}.$(date '+%Y%m%d_%H%M%S')"
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
find /tmp -maxdepth 1 -name '.com.google.Chrome*' -mmin +60 -exec rm -rf {} \; 2>/dev/null
find /tmp -maxdepth 1 -name 'chrome_crashpad*' -mmin +60 -exec rm -rf {} \; 2>/dev/null
find /tmp -maxdepth 1 -name 'scoped_dir*' -mmin +60 -exec rm -rf {} \; 2>/dev/null
echo "  /tmp: Chrome一時ファイルを削除"

# 残留Chrome/chromedriverプロセスのkill（30分以上経過したものをゾンビとみなす）
# Sidekiqジョブ完了時のensureで終わらない異常ケースを定期的に救済
ZOMBIE_PIDS=$(ps -eo pid,user,etimes,comm 2>/dev/null | awk '$2 == "smart" && $3 > 1800 && $4 ~ /chrome/ {print $1}')
if [ -n "$ZOMBIE_PIDS" ]; then
  ZOMBIE_COUNT=$(echo "$ZOMBIE_PIDS" | wc -l)
  echo "  残留Chromeプロセス（30分超）: ${ZOMBIE_COUNT}個 → kill -9"
  echo "$ZOMBIE_PIDS" | xargs -r kill -9 2>/dev/null
fi

# Chromeダウンロードフォルダの安全網（フォーム送信時の自動DL対策の二重防御）
# 1時間以上前のファイルを削除。Selenium側でダウンロード自体を抑止しているため通常は空のはず
for dl_dir in "$HOME/Downloads" "/root/Downloads"; do
  if [ -d "$dl_dir" ]; then
    find "$dl_dir" -maxdepth 1 -type f -mmin +60 -delete 2>/dev/null
    echo "  $dl_dir: 1時間以上前のダウンロードファイルを削除"
  fi
done

# ディスク使用率チェック
DISK_USAGE=$(df -h "$APP_DIR" | tail -1 | awk '{print $5}' | tr -d '%')
echo "  ディスク使用率: ${DISK_USAGE}%"

if [ "$DISK_USAGE" -gt 90 ] 2>/dev/null; then
  echo "  [警告] ディスク使用率が90%を超えています！"
  # sidekiq-okuriteを停止してこれ以上のディスク消費を防止
  # （無印sidekiqはtcarepro用の別サービスなので触らない）
  sudo systemctl stop sidekiq-okurite 2>/dev/null
  echo "  [対処] sidekiq-okuriteを停止しました。ディスク容量を確認してください。"
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') [cleanup] 完了"
