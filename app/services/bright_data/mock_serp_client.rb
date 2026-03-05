module BrightData
  class MockSerpClient
    def search(query:, **_opts)
      {
        "organic_results" => [
          { "title" => "#{query} - テスト結果1", "link" => "https://example.com/1", "snippet" => "テスト説明" },
          { "title" => "#{query} - テスト結果2", "link" => "https://example.com/2", "snippet" => "テスト説明" }
        ]
      }
    end

    def batch_search(queries, delay_between: 0)
      queries.map { |q| { "query" => q, "result" => search(query: q), "timestamp" => Time.current.iso8601 } }
    end
  end
end
