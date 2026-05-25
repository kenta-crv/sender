class UnsubscribesController < ApplicationController
  skip_before_action :verify_authenticity_token

  def show
    customer = Customer.find_by(
      unsubscribe_token: params[:token]
    )

    if customer.blank?
      render plain: '無効なURLです', status: :not_found
      return
    end

    customer.update!(
      fobbiden: 't'
    )

    render inline: <<~HTML
      <!DOCTYPE html>
      <html lang="ja">
      <head>
        <meta charset="UTF-8">
        <title>配信停止完了</title>

        <style>
          body {
            font-family: sans-serif;
            background: #f5f7fb;
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100vh;
            margin: 0;
          }

          .box {
            background: white;
            padding: 40px;
            border-radius: 12px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.08);
            text-align: center;
          }

          h1 {
            margin-bottom: 12px;
          }

          p {
            color: #666;
          }
        </style>
      </head>

      <body>
        <div class="box">
          <h1>配信停止しました</h1>
          <p>今後フォーム送信は行われません。</p>
        </div>
      </body>
      </html>
    HTML
  end
end