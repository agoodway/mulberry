# Crawler System Implementation

This document provides technical implementation details for the Mulberry web crawler system.

## Architecture Overview

The crawler follows a supervisor-based OTP architecture with these core components:

```
Mulberry.Crawler.Supervisor
├── RateLimiter (GenServer)
├── RobotsTxt (GenServer)
├── WorkerSupervisor (DynamicSupervisor)
└── OrchestratorSupervisor (DynamicSupervisor)
    └── Orchestrator(s) (GenServer)
        └── Worker(s) (GenServer)
```

## Core Modules

### Mulberry.Crawler (Public API)

Entry point with three crawling modes:

- `crawl_urls/2` - Crawl a specific list of URLs
- `crawl_website/2` - Crawl a website starting from a URL, following links
- `crawl_from_sitemap/2` - Discover and crawl URLs from sitemap.xml

All functions accept options including:
- `:max_workers` - Concurrent worker count (default: 5)
- `:rate_limit` - Requests/second per domain (default: 1.0)
- `:max_depth` - Link following depth for website mode (default: 3)
- `:retriever` - HTTP retriever module (default: `Mulberry.Retriever.Req`)
- `:respect_robots_txt` - Honor robots.txt (default: true)
- `:async` - Return orchestrator PID immediately (default: false)
- `:include_patterns` / `:exclude_patterns` - URL filtering regexes

### Mulberry.Crawler.Orchestrator

GenServer managing the crawl lifecycle:

**State:**
- URL queue (`:queue` data structure)
- Visited URLs (MapSet for O(1) deduplication)
- Active workers map (PID -> URL/depth info)
- Collected results list
- Statistics accumulator

**Message Flow:**
1. Receives URLs via `crawl_urls/2` or `crawl_website/2`
2. Spawns workers up to `max_workers` limit
3. Handles `{:crawl_result, worker_pid, url, result}` messages
4. Tracks worker crashes via `Process.monitor/1`
5. Calls completion callbacks when queue empty and no active workers

### Mulberry.Crawler.Worker

GenServer performing actual page fetching:

1. Receives URL and context via `crawl/3`
2. Normalizes URL via URLManager
3. Fetches document using configured retriever
4. Calls crawler implementation callbacks:
   - `extract_data/2` - Pull data from document
   - `extract_urls/2` - Discover new URLs
5. Reports result to orchestrator
6. Invokes `on_url_success/3` or `on_url_failure/3` callbacks

### Mulberry.Crawler.Behaviour

Defines the interface for custom crawler implementations:

```elixir
@callback should_crawl?(url, context) :: boolean()
@callback extract_data(document, url) :: {:ok, map()} | {:error, any()}
@callback extract_urls(document, base_url) :: {:ok, [url]} | {:error, any()}
@callback on_url_success(url, result, context) :: :ok | {:error, any()}  # optional
@callback on_url_failure(url, reason, context) :: :ok | {:error, any()}  # optional
@callback on_complete(results) :: :ok | {:error, any()}  # optional
```

### Mulberry.Crawler.Default

Built-in implementation providing:
- Same-domain filtering for website mode
- Link extraction from `<a href>` elements
- Metadata extraction (title, description, meta tags)
- Structured data extraction (JSON-LD, Open Graph, Twitter Cards)
- URL scheme filtering (skip mailto:, javascript:, file extensions)

## Supporting Modules

### Mulberry.Crawler.RateLimiter

Token bucket rate limiter (GenServer):

- Per-domain buckets with configurable capacity and refill rate
- `consume_token/1` - Non-blocking, returns `:ok` or `{:error, :rate_limited}`
- `wait_and_consume_token/2` - Blocking with timeout
- Automatic bucket creation on first request

Implementation uses monotonic time for accurate token refill calculations.

### Mulberry.Crawler.RobotsTxt

robots.txt parser and cache (GenServer with ETS):

- Fetches and parses robots.txt per domain
- Caches with configurable TTL (default: 1 hour)
- Supports User-agent, Allow, Disallow, Crawl-delay, Sitemap directives
- Pattern matching with `*` wildcard and `$` end anchor
- Uses pre-compiled regexes to prevent ReDoS attacks

### Mulberry.Crawler.URLManager

URL utilities:

- `normalize_url/1` - Canonical form (lowercase scheme/host, sorted query params, no fragments)
- `resolve_url/2` - Resolve relative URLs against base
- `same_domain?/2` - Domain matching including subdomains
- `compile_patterns/1` - Compile regex patterns for URL filtering
- `filter_urls/2` - Apply domain and path filters

### Mulberry.Crawler.Sitemap

Sitemap discovery and parsing:

- `discover_sitemaps/2` - Check robots.txt and common locations
- `fetch_and_parse/2` - Parse XML sitemaps and indexes
- Handles gzipped sitemaps (`.xml.gz`)
- Recursive sitemap index following with depth limit

### Mulberry.Crawler.Stats

Pure functional statistics tracking:

- URL counts (crawled, failed, discovered, filtered, robots-blocked)
- HTTP status code breakdown
- Error categorization (timeout, DNS, connection, parse, rate_limited, http_error)
- Per-domain metrics with average response times
- Duration tracking

### Mulberry.Crawler.StructuredData

Extracts embedded structured data:

- **JSON-LD**: `<script type="application/ld+json">` blocks
- **Open Graph**: `<meta property="og:*">` tags
- **Twitter Card**: `<meta name="twitter:*">` tags

Uses allowlisted atoms to prevent atom table exhaustion.

## CLI Interface

### Mix.Tasks.Crawl

Command-line interface supporting:

**Modes:**
- `--url URL` - Website crawl
- `--urls FILE` - URL list from file
- `--sitemap DOMAIN` - Sitemap-based crawl

**Output Formats:**
- `--format console` - Print to stdout
- `--format jsonl --output FILE` - JSONL file
- `--format markdown --output-dir DIR` - Individual/combined markdown files

**Options:**
- `--max-depth N` - Crawl depth
- `--max-workers N` - Concurrency
- `--rate-limit N` - Requests/second
- `--retriever {req,playwright,scraping_bee}` - HTTP backend
- `--include-pattern REGEX` - URL inclusion filter (repeatable)
- `--exclude-pattern REGEX` - URL exclusion filter (repeatable)
- `--no-robots` - Skip robots.txt
- `--combine-files` - Single markdown output
- `--resume` - Skip existing files

### Mulberry.Crawler.CLI.Progress

Progress display with verbosity levels:
- `:quiet` - Errors only
- `:normal` - Progress bar and summary
- `:verbose` - Per-URL output
- `:debug` - Full logging

## Data Flow

```
User Request
    │
    ▼
Mulberry.Crawler.crawl_*
    │
    ├─► Supervisor.start_crawler
    │       │
    │       ▼
    │   Orchestrator.init
    │       │
    │       ▼
    └─► Orchestrator.crawl_*
            │
            ▼
        URL Queue ◄──────────────────┐
            │                        │
            ▼                        │
        spawn_workers                │
            │                        │
            ▼                        │
        RateLimiter.consume_token    │
            │                        │
            ▼                        │
        Worker.crawl                 │
            │                        │
            ├─► RobotsTxt.allowed?   │
            │                        │
            ├─► Retriever.get        │
            │                        │
            ├─► crawler_impl.extract_data
            │                        │
            ├─► crawler_impl.extract_urls
            │       │                │
            │       └────────────────┘
            │
            ▼
        {:crawl_result, ...}
            │
            ▼
        Orchestrator (collect results)
            │
            ▼
        await_completion → {:ok, results}
```

## Custom Crawler Example

```elixir
defmodule MyBlogCrawler do
  @behaviour Mulberry.Crawler.Behaviour

  @impl true
  def should_crawl?(url, context) do
    String.contains?(url, "/blog/") &&
      context.current_depth <= context.max_depth
  end

  @impl true
  def extract_data(document, url) do
    {:ok, %{
      url: url,
      title: document.title,
      content: document.markdown,
      author: extract_author(document),
      published_at: extract_date(document)
    }}
  end

  @impl true
  def extract_urls(document, base_url) do
    Mulberry.Crawler.Default.extract_urls(document, base_url)
  end

  @impl true
  def on_complete(results) do
    File.write!("blog_posts.json", Jason.encode!(results))
    :ok
  end

  defp extract_author(doc), do: # ...
  defp extract_date(doc), do: # ...
end

# Usage
{:ok, results} = Mulberry.Crawler.crawl_website(
  "https://example.com/blog",
  crawler_impl: MyBlogCrawler,
  max_depth: 2
)
```

## Performance Considerations

1. **Concurrency**: `max_workers` controls parallelism; higher values increase throughput but consume more memory
2. **Rate Limiting**: Token bucket prevents overwhelming target servers; adjust per domain requirements
3. **Memory**: Results accumulate in orchestrator state; consider streaming for large crawls
4. **URL Deduplication**: MapSet provides O(1) visited checks; normalized URLs prevent duplicates
5. **robots.txt Caching**: ETS with `read_concurrency` for fast parallel lookups
6. **Pattern Compilation**: URL patterns compiled once at orchestrator init

## Error Handling

- Worker crashes monitored; orchestrator spawns replacements
- Rate limiting retries with backoff (100ms delay)
- robots.txt failures default to permissive (allow all)
- Fetch errors categorized for statistics and reported via callbacks
- Partial results returned even if some URLs fail
