# Test script for multi-module search functionality
IO.puts("Testing multi-module search functionality...\n")

# Test 1: Multi-module search with Brave and Reddit
IO.puts("Test 1: Multi-module search")
result = Mulberry.research("elixir programming",
  search_modules: [
    %{
      module: Mulberry.Search.Brave,
      options: %{result_filter: "web,query"}
    },
    %{
      module: Mulberry.Search.Reddit,
      options: %{sort: "top", timeframe: "month", subreddit: "elixir"},
      weight: 1.5  # Give Reddit results higher weight
    }
  ],
  max_sources: 3,
  verbose: true
)

case result do
  {:ok, research_result} ->
    IO.puts("\nSuccess! Found #{length(research_result.sources)} sources")
    IO.puts("Summary: #{String.slice(research_result.summary, 0, 200)}...")
  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end

# Test 2: Single module search (backward compatibility)
IO.puts("\n\nTest 2: Single module search (backward compatibility)")
result2 = Mulberry.research("elixir tips",
  search_module: Mulberry.Search.Reddit,
  search_module_options: %{sort: "new"},
  max_sources: 2
)

case result2 do
  {:ok, research_result} ->
    IO.puts("Success! Found #{length(research_result.sources)} sources")
  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end

IO.puts("\nAll tests completed!")