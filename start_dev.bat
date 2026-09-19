@echo off
rem 開発環境の起動（Windows）。このファイルをプロジェクトの一番上で実行する。
rem Redis / Sidekiq / Rails（3002番） / ngrok が別ウィンドウで起動する。
rem 状態確認は macOS では ./start_dev.sh check を使う。

cd /d "%~dp0"

start "Redis" cmd /k "echo === Redis === && redis-server"
start "Sidekiq" cmd /k "echo === Sidekiq === && bundle exec sidekiq -C config/sidekiq.yml"
start "ngrok" cmd /k "echo === ngrok === && ngrok http 3002"
start "Rails" cmd /k "echo === Rails === && bundle exec rails server -p 3002"

echo.
echo 4つのサービスを別ウィンドウで起動しました。
echo 停止する場合は、各ウィンドウで Ctrl+C を押すか、ウィンドウを閉じてください。
echo.
pause
