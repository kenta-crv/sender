# app/services/gpt_article_generator.rb
class GptArticleGenerator
  def self.generate_body(column)
    client = OpenAI::Client.new

    response = client.chat(
      parameters: {
        model: "gpt-4.1-mini",
        messages: [
          { role: "system", content: "You are a professional Japanese writer." },
          { role: "user", content: "次のタイトルで本文を生成して: #{column.title}" }
        ]
      }
    )

    response.dig("choices", 0, "message", "content")
  end
end
