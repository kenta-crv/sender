@echo off
rem 自動発信システム 開発環境 一括起動スクリプト（Windows用）
rem
rem 使い方:
rem   1. sender ディレクトリに移動
rem   2. start_dev.bat をダブルクリック
rem → 4つのコマンドプロンプトが開き、Redis / Sidekiq / ngrok / Rails が起動します。

cd /d "%~dp0"

start "Redis" cmd /k "echo === Redis === && redis-server"
start "Sidekiq" cmd /k "echo === Sidekiq === && bundle exec sidekiq"
start "ngrok" cmd /k "echo === ngrok === && ngrok http 3000"
start "Rails" cmd /k "echo === Rails === && bundle exec rails server"

echo.
echo 4つのサービスを別ウィンドウで起動しました。
echo 停止する場合は、各ウィンドウで Ctrl+C を押すか、ウィンドウを閉じてください。
echo.
pause
