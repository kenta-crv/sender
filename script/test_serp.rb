client = BrightData::SerpClient.new(
  api_key: ENV["BRIGHT_DATA_API_KEY"],
  zone: ENV["BRIGHT_DATA_ZONE"]
)

result = client.search(query: "トヨタ自動車 会社概要")

puts "status_code: #{result['status_code']}"
puts "body class: #{result['body'].class}"
puts "body length: #{result['body'].length}"

puts "----- BODY HEAD -----"
puts result["body"][0, 1000]
