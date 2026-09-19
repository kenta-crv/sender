#!/bin/bash
# 開発環境の起動は、このスクリプトだけを使う。
#   ./start_dev.sh         止まっているものだけ起動し、最後に状態を表示する
#   ./start_dev.sh check   起動せず、状態だけ表示する
#
# 対象: Redis / Sidekiq / Rails（3002番） / ngrok

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORT=3002
NGROK_API="http://127.0.0.1:4040/api/tunnels"

export PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"
if [ -f "$PROJECT_DIR/.ruby-version" ]; then
  export RBENV_VERSION
  RBENV_VERSION="$(cat "$PROJECT_DIR/.ruby-version")"
fi
unset BUNDLE_PATH BUNDLE_USER_CONFIG
export DISABLE_SPRING=1

cd "$PROJECT_DIR"

ok_count=0
ng_count=0

say_ok() {
  echo "OK  $1"
  ok_count=$((ok_count + 1))
}

say_ng() {
  echo "NG  $1"
  ng_count=$((ng_count + 1))
}

redis_up() {
  redis-cli ping 2>/dev/null | grep -q PONG
}

rails_up() {
  curl -sS -o /dev/null --max-time 3 "http://127.0.0.1:${PORT}/"
}

port_listening() {
  lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

sidekiq_up() {
  pgrep -f 'sidekiq.*(okurite|config/sidekiq.yml)|sidekiq -C config/sidekiq.yml' >/dev/null 2>&1
}

ngrok_public_url() {
  curl -sS --max-time 3 "$NGROK_API" 2>/dev/null | python3 -c "
import json,sys
try:
    data=json.load(sys.stdin)
except Exception:
    sys.exit(0)
for t in data.get('tunnels') or []:
    url=(t.get('public_url') or '')
    if url.startswith('https://'):
        print(url)
        break
"
}

current_env_ngrok() {
  if [ -f "$PROJECT_DIR/.env" ]; then
    grep '^NGROK_URL=' "$PROJECT_DIR/.env" | tail -n 1 | cut -d= -f2- | tr -d '\r'
  fi
}

write_env_ngrok() {
  local url="$1"
  python3 - "$PROJECT_DIR/.env" "$url" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
url = sys.argv[2]
if not path.exists():
    path.write_text(f"NGROK_URL={url}\n")
    raise SystemExit
text = path.read_text()
lines = text.splitlines(True)
out = []
found = False
for line in lines:
    if line.startswith("NGROK_URL="):
        out.append(f"NGROK_URL={url}\n")
        found = True
    else:
        out.append(line)
if not found:
    if out and not out[-1].endswith("\n"):
        out[-1] = out[-1] + "\n"
    out.append(f"NGROK_URL={url}\n")
path.write_text("".join(out))
PY
}

# Terminal.app で起動する。Cursor のコマンドが終わってもプロセスが残る。
launch_terminal() {
  local title="$1"
  local inner="$2"
  osascript <<EOF
tell application "Terminal"
  activate
  do script "echo '=== ${title} ==='; ${inner}"
end tell
EOF
}

ruby_env="export PATH='$HOME/.rbenv/shims:$HOME/.rbenv/bin:/usr/local/bin:/opt/homebrew/bin:\$PATH'; export RBENV_VERSION='$RBENV_VERSION'; unset BUNDLE_PATH BUNDLE_USER_CONFIG; export DISABLE_SPRING=1; cd '$PROJECT_DIR'"

start_redis() {
  if redis_up; then
    echo "Redis は起動済みです。"
    return
  fi
  echo "Redis を起動します。"
  launch_terminal "Redis" "redis-server"
}

start_rails() {
  if rails_up; then
    echo "Rails は起動済みです（ポート ${PORT}）。"
    return
  fi
  echo "Rails を起動します。"
  launch_terminal "Rails" "$ruby_env; bundle exec rails server -p ${PORT} -b 127.0.0.1"
}

start_sidekiq() {
  if sidekiq_up; then
    echo "Sidekiq は起動済みです。"
    return
  fi
  echo "Sidekiq を起動します。"
  launch_terminal "Sidekiq" "$ruby_env; bundle exec sidekiq -C config/sidekiq.yml"
}

start_ngrok() {
  if port_listening 4040 && [ -n "$(ngrok_public_url)" ]; then
    echo "ngrok は起動済みです。"
    return
  fi
  if port_listening 4040; then
    echo "ngrok の管理画面は開いていますが、公開URLがまだ取れません。数秒待って ./start_dev.sh check を実行してください。"
    return
  fi
  echo "ngrok を起動します。"
  launch_terminal "ngrok" "ngrok http ${PORT}"
}

wait_for() {
  local name="$1"
  local fn="$2"
  local n=0
  while [ "$n" -lt 20 ]; do
    if eval "$fn"; then
      return 0
    fi
    n=$((n + 1))
    sleep 1
  done
  echo "${name} の起動待ちが終わりました。状態確認で結果を見てください。"
}

sync_ngrok_url() {
  local public
  public="$(ngrok_public_url)"
  [ -z "$public" ] && return
  local current
  current="$(current_env_ngrok)"
  if [ "$current" = "$public" ]; then
    return
  fi
  write_env_ngrok "$public"
  echo "注意: .env の NGROK_URL を次の値に合わせました。"
  echo "      $public"
  echo "      すでに Rails が動いている場合は、Rails を一度止めてから ./start_dev.sh を再実行してください。"
}

check_all() {
  echo ""
  echo "===== 起動確認 ====="

  if redis_up; then
    say_ok "Redis（待ち行列）  redis-cli ping が通っています"
  else
    say_ng "Redis が応答しません。Terminal の Redis 画面、または redis-server"
  fi

  if rails_up; then
    say_ok "Rails（画面）  http://127.0.0.1:${PORT}/ が応答しています"
  else
    say_ng "Rails がポート ${PORT} で応答しません。Terminal の Rails 画面"
  fi

  if sidekiq_up; then
    say_ok "Sidekiq（裏作業。発信とフォーム送信の本体）  プロセスがあります"
  else
    say_ng "Sidekiq が動いていません。Terminal の Sidekiq 画面。管理者ログイン後の確認先: /sidekiq"
  fi

  local public
  public="$(ngrok_public_url)"
  if [ -n "$public" ]; then
    say_ok "ngrok（外部から Rails へ届ける入口）  $public"
  else
    say_ng "ngrok の公開URLが取れません。http://127.0.0.1:4040 または Terminal の ngrok 画面"
  fi

  local env_url
  env_url="$(current_env_ngrok)"
  if [ -n "$public" ] && [ -n "$env_url" ] && [ "$public" = "$env_url" ]; then
    say_ok ".env の NGROK_URL が ngrok のURLと一致しています"
  elif [ -z "$public" ]; then
    say_ng ".env の NGROK_URL は、ngrok が起動してから照合します"
  else
    say_ng ".env の NGROK_URL が ngrok のURLと違います。電話会社からの通知が届きません"
  fi

  echo ""
  echo "結果: OK ${ok_count} / NG ${ng_count}"
  echo "失敗の見方:"
  echo "  - 発信もフォーム送信も始まらない → Sidekiq と Redis の Terminal"
  echo "  - 画面が開かない → Rails の Terminal"
  echo "  - 電話は掛かるが会話が続かない → ngrok と NGROK_URL"
  echo "  - 裏作業の失敗一覧 → 管理者でログイン後に /sidekiq"
  echo ""
  if [ "$ng_count" -gt 0 ]; then
    return 1
  fi
  return 0
}

cmd="${1:-start}"

case "$cmd" in
  check)
    check_all
    ;;
  start)
    start_redis
    start_rails
    start_sidekiq
    start_ngrok
    wait_for "Sidekiq" "sidekiq_up"
    wait_for "ngrok" "[ -n \"\$(ngrok_public_url)\" ]"
    sync_ngrok_url
    check_all
    ;;
  *)
    echo "使い方: ./start_dev.sh  または  ./start_dev.sh check"
    exit 1
    ;;
esac
