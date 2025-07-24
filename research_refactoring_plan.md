# Enhanced Research Module Refactoring Plan - Multiple Search Modules

## Overview
Refactor the research module to support searching across multiple search modules simultaneously, with module-specific options for each.

## Key Changes

### 1. Update `Mulberry.Research.Chain` Schema
Add new fields to support multiple search modules:
```elixir
# Instead of single search_module:
field(:search_modules, {:array, :map}, default: [])
# Each map contains:
# %{
#   module: Mulberry.Search.Brave,
#   options: %{},
#   weight: 1.0  # Optional weighting for result ranking
# }
```

### 2. Update `Mulberry.Research` Module
Support both single and multiple search module configurations:

```elixir
# Single module (backward compatible):
Mulberry.research("elixir programming",
  search_module: Mulberry.Search.Brave
)

# Multiple modules with options:
Mulberry.research("elixir programming",
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
  ]
)
```

### 3. Update `Mulberry.Research.Web` Module

**Key changes in `perform_searches/3`**:
- Execute searches across all configured modules in parallel
- Aggregate results from different sources
- Apply module-specific weights if provided
- Deduplicate results by URL
- Maintain source attribution (which module found each result)

**New structure**:
```elixir
defp perform_searches(queries, %Chain{} = chain, opts) do
  search_modules = get_search_modules(chain)
  
  # Parallel search across all modules
  results = search_modules
  |> Task.async_stream(fn {module, module_opts} ->
    perform_module_searches(queries, module, module_opts, chain)
  end, timeout: 30_000)
  |> Enum.flat_map(fn
    {:ok, results} -> results
    _ -> []
  end)
  |> deduplicate_and_rank(chain)
  
  {:ok, results}
end
```

### 4. Result Aggregation & Ranking
- Combine results from all search modules
- Apply weights based on source module
- Deduplicate by URL (keep highest weighted)
- Preserve metadata about which module(s) found each result
- Sort by relevance score × module weight

### 5. Backward Compatibility
- If `search_module` (singular) is provided, convert to modules list
- Default to Brave search if no modules specified
- All existing code continues to work

### 6. Update Mix Tasks
Support multiple search modules in CLI:
```bash
# Single module (backward compatible)
mix research "elixir tips" --search-module brave

# Multiple modules with JSON config
mix research "elixir tips" --search-modules '[
  {"module": "brave", "options": {}},
  {"module": "reddit", "options": {"sort": "top", "subreddit": "elixir"}}
]'
```

## Implementation Details

### 1. Chain Schema
```elixir
field(:search_modules, {:array, :map}, default: [])
# Computed field for backward compatibility
field(:search_module, :any, virtual: true)
```

### 2. Module Configuration
```elixir
defp normalize_search_modules(opts) do
  cond do
    modules = opts[:search_modules] -> modules
    module = opts[:search_module] -> 
      [%{module: module, options: opts[:search_module_options] || %{}}]
    true -> 
      [%{module: Mulberry.Search.Brave, options: %{}}]
  end
end
```

### 3. Parallel Search Execution
- Use `Task.async_stream` for concurrent searches
- Handle failures gracefully (log but don't fail entire search)
- Merge results maintaining source attribution

### 4. Enhanced Document Structure
- Add metadata to track which module(s) found each document
- Preserve module-specific metadata (e.g., Reddit's upvotes, Brave's ranking)

## Benefits
- Search multiple sources simultaneously for comprehensive results
- Module-specific configuration for optimal results
- Weighted ranking allows prioritizing certain sources
- Parallel execution for better performance
- Extensible to any number of search modules
- Full backward compatibility

## Example Use Cases

1. **Academic Research**: Combine web search with Reddit discussions
2. **Technical Topics**: Search documentation (Brave) + community insights (Reddit)
3. **Current Events**: Multiple news sources with different perspectives
4. **Product Research**: Official sources + user reviews/discussions

## Implementation Steps

1. Update Chain schema with search_modules field
2. Add module normalization logic to Research module
3. Refactor Web module's perform_searches to support multiple modules
4. Implement parallel search execution with Task.async_stream
5. Add result deduplication and ranking logic
6. Update mix tasks to support new options
7. Add comprehensive tests for multi-module searches
8. Update documentation with examples
