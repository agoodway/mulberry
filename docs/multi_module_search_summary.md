# Multi-Module Search Implementation Summary

## Overview
Successfully implemented support for searching across multiple search modules simultaneously in the Mulberry research functionality.

## Key Changes

### 1. Schema Updates
- Added `search_modules` field to `Research.Chain` schema for multi-module configuration
- Maintained backward compatibility with existing `search_module` and `search_module_options` fields

### 2. Core Implementation
- Refactored `perform_searches` in `Research.Web` to support parallel execution across modules
- Implemented `Task.async_stream` for concurrent searches with proper timeout handling
- Added result deduplication by URL while preserving highest-weighted results
- Added configurable weighting system for ranking results from different sources

### 3. Mix Tasks
- Updated both `mix search` and `mix research` tasks to support the new options
- Added `--search-modules` flag for JSON configuration of multiple modules
- Maintained backward compatibility with `--search-module` flag

### 4. Testing
- Created comprehensive test suite in `test/research/multi_module_test.exs`
- Tests cover normalization, backward compatibility, and configuration handling

## Usage Examples

### Using Multiple Search Modules
```bash
# Search with Brave and Reddit, giving Reddit results 1.5x weight
mix research "elixir programming" --search-modules '[
  {"module": "brave", "options": {}},
  {"module": "reddit", "options": {"sort": "top"}, "weight": 1.5}
]'
```

### Programmatic Usage
```elixir
# Multiple modules
Mulberry.research("elixir tips",
  search_modules: [
    %{module: Mulberry.Search.Brave, options: %{}},
    %{module: Mulberry.Search.Reddit, options: %{subreddit: "elixir"}, weight: 1.5}
  ]
)

# Single module (backward compatible)
Mulberry.research("elixir tips",
  search_module: Mulberry.Search.Reddit,
  search_module_options: %{sort: "top"}
)
```

## Implementation Details

### Module Configuration Structure
```elixir
%{
  module: Mulberry.Search.Brave,     # The search module
  options: %{},                      # Module-specific options
  weight: 1.0                        # Result weighting (default: 1.0)
}
```

### Result Processing
1. Searches are executed in parallel across all configured modules
2. Results are collected and deduplicated by URL
3. When duplicates exist, the result with highest weight is kept
4. Final results are sorted by weight (descending)

## Benefits
- Improved search coverage by combining multiple sources
- Parallel execution for better performance
- Flexible weighting system for result ranking
- Maintains backward compatibility with existing code
- Clean, extensible architecture for adding new search modules