# Mulberry Mix Tasks Guide

This document provides comprehensive information about all custom Mix tasks available in Mulberry.

## Overview

Mulberry provides several Mix tasks for common operations:

- `mix business_listings` - Fetch business listings from DataForSEO and save to JSON
- `mix fetch_url` - Fetch and process web pages
- `mix search` - Search various providers (Brave, Google, Reddit, etc.)
- `mix text` - Text processing operations (summarization, classification, etc.)
- `mix research` - Conduct comprehensive research on topics

## Task Reference

### `mix business_listings`

Fetches business listings from Google Maps via the DataForSEO Business Listings API and saves results to a JSON file.

#### Usage
```bash
mix business_listings [options]
```

#### Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--categories` | `-c` | Comma-separated category IDs (e.g., "pizza_restaurant,italian_restaurant") | - |
| `--location` | `-l` | Location coordinate "latitude,longitude,radius_km" | - |
| `--title` | `-t` | Business title/name to search for (max 200 chars) | - |
| `--description` | `-d` | Business description to search for (max 200 chars) | - |
| `--claimed` | - | Only include Google Maps verified businesses (flag) | false |
| `--filters` | `-f` | Filter condition "field,operator,value" (repeatable, max 8) | - |
| `--order-by` | `-s` | Sort rule "field,direction" (repeatable, max 3) | - |
| `--limit` | `-n` | Maximum number of results (max: 1000) | 100 |
| `--offset` | - | Pagination offset for results | - |
| `--output` | `-o` | Output JSON file path | business_listings.json |

#### Filter Operators

Valid operators for `--filters`:
- `<`, `<=`, `>`, `>=` - Numeric comparisons
- `=`, `!=` - Equality checks
- `like`, `not_like` - Pattern matching
- `regex`, `not_regex` - Regular expression matching

#### Common Category IDs

- `restaurant` - Restaurants (general)
- `pizza_restaurant` - Pizza restaurants
- `italian_restaurant` - Italian restaurants
- `cafe` - Cafes
- `coffee_shop` - Coffee shops
- `bar` - Bars
- `hotel` - Hotels
- `gas_station` - Gas stations
- `grocery_store` - Grocery stores
- `pharmacy` - Pharmacies

#### Output Format

The JSON file contains:
- `total_count` - Total matching businesses
- `fetched_count` - Number of businesses in this result
- `fetched_at` - ISO 8601 timestamp
- `elapsed_ms` - Time taken in milliseconds
- `search_params` - Search parameters used
- `items` - Array of business listing objects

Each business listing includes: title, description, category, address, phone, website, ratings, hours, location coordinates, and more.

#### Examples

```bash
# Search for pizza restaurants in NYC (5km radius)
mix business_listings -c pizza_restaurant -l "40.7128,-74.0060,5"

# Search by business name in Seattle
mix business_listings -t "Starbucks" -l "47.6062,-122.3321,20"

# High-rated restaurants in LA with filters
mix business_listings \
  -c restaurant \
  -l "34.0522,-118.2437,10" \
  -f "rating.value,>,4.5" \
  -f "rating.votes_count,>,100" \
  -s "rating.value,desc" \
  -n 50 \
  -o la_restaurants.json

# Multiple categories with ordering
mix business_listings \
  -c "pizza_restaurant,italian_restaurant" \
  -l "41.8781,-87.6298,8" \
  -s "rating.value,desc" \
  -s "rating.votes_count,desc" \
  -n 200

# Only verified businesses
mix business_listings -c cafe -l "37.7749,-122.4194,3" --claimed

# Search with title and complex filters
mix business_listings \
  -t "Pizza" \
  -l "40.7128,-74.0060,10" \
  -f "rating.value,>=,4.0" \
  -f "is_claimed,=,true" \
  --limit 100
```

#### Environment Variables

Required for this task:
- `DATAFORSEO_USERNAME` - Your DataForSEO API username
- `DATAFORSEO_PASSWORD` - Your DataForSEO API password

Get credentials at: https://app.dataforseo.com/api-access

## Task Reference

### `mix fetch_url`

Fetches a URL using the Playwright retriever for JavaScript-heavy websites.

#### Usage
```bash
mix fetch_url URL [options]
```

#### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--headless` | Run browser in headless mode | true |
| `--browser` | Browser type: chromium, firefox, or webkit | chromium |
| `--stealth` | Enable stealth mode | true |
| `--timeout` | Timeout in milliseconds | 30000 |
| `--wait-for` | CSS selector to wait for | body |
| `--save` | Save HTML content to specified file | - |
| `--show-text` | Show extracted text content instead of HTML | false |
| `--markdown` | Convert HTML to Markdown format | false |
| `--title` | Generate a title for the page content using AI | false |

#### Examples

```bash
# Basic usage
mix fetch_url https://example.com

# Save to file
mix fetch_url https://example.com --save output.html

# Use Firefox in non-headless mode (visible browser)  
mix fetch_url https://example.com --browser firefox --no-headless

# Show text content only
mix fetch_url https://example.com --show-text

# Convert to Markdown
mix fetch_url https://example.com --markdown

# Save as Markdown file
mix fetch_url https://example.com --markdown --save output.md

# Wait for specific element
mix fetch_url https://example.com --wait-for "#content"

# Generate a title for the page
mix fetch_url https://example.com --title

# Show text and generate title
mix fetch_url https://example.com --show-text --title
```

### `mix search`

Performs searches using various providers including Brave, Google, Reddit, Facebook Ads, YouTube, and more.

#### Usage
```bash
mix search [TYPE] QUERY [options]
```

#### Search Types

- `brave` - Web search using Brave Search API (default)
- `google` - Google search using ScrapeCreators API
- `reddit` - Reddit post search using ScrapeCreators API
- `facebook_ads` - Facebook ads search using ScrapeCreators API
- `facebook_ad_companies` - Facebook ad companies search using ScrapeCreators API
- `google_ads` - Google ads search using ScrapeCreators API
- `youtube` - YouTube search using ScrapeCreators API

#### Common Options

| Option | Description | Default |
|--------|-------------|---------|
| `--limit` | Maximum number of results | 10 |
| `--format` | Output format: text, json, or markdown | text |
| `--save` | Save results to specified file | - |
| `--verbose` | Show detailed information | false |

#### Provider-Specific Options

##### Brave Search
- `--result-filter` - Filter results, e.g., "query,web" (default: "query,web")

##### Google Search
- `--region` - 2 letter country code, e.g., US, UK, CA (optional)

##### Reddit Search
- `--sort` - Sort order: relevance, hot, top, new, comments
- `--timeframe` - Time filter: all, year, month, week, day, hour
- `--subreddit` - Filter by specific subreddit
- `--after` - Pagination token for next page
- `--trim` - Get trimmed responses (boolean)

##### Facebook Ads Search
- `--search-by` - Search by: company_name (default) or page_id
- `--country` - 2-letter country code (e.g., US, GB)
- `--status` - Ad status: ACTIVE (default), INACTIVE, or ALL
- `--media-type` - Media type: ALL (default), image, video, or meme
- `--cursor` - Pagination cursor for next page
- `--trim` - Get trimmed responses (boolean)

##### Facebook Ad Companies Search
- `--cursor` - Pagination cursor for next page

##### Google Ads Search
- `--advertiser-id` - Search by advertiser ID instead of domain
- `--topic` - Topic filter: political, etc. (requires --region for political)
- `--region` - Region filter (e.g., US, UK, CA)
- `--cursor` - Pagination cursor for next page

##### YouTube Search
- `--upload-date` - Upload date filter: lastHour, today, thisWeek, thisMonth, thisYear
- `--sort-by` - Sort order: relevance, uploadDate, viewCount, rating
- `--filter` - Filter by type: video, channel, playlist
- `--continuation-token` - Pagination token for next page

#### Examples

```bash
# Default Brave search
mix search "elixir programming"

# Google search with region
mix search google "local news" --region UK

# Reddit search with options
mix search reddit "elixir tips" --sort top --timeframe month

# Save results as JSON
mix search reddit "web scraping" --format json --save results.json

# Filter by subreddit
mix search reddit "tips" --subreddit elixir

# YouTube with filters
mix search youtube "phoenix framework" --sort-by viewCount --upload-date thisMonth

# Facebook ads search
mix search facebook_ads "Nike" --country US --status ACTIVE

# Google ads search
mix search google_ads "nike.com" --topic political --region US
```

### `mix text`

Performs text processing operations using Mulberry.Text module.

#### Usage
```bash
mix text OPERATION [OPTIONS]
```

#### Operations

- `summarize` - Generate a summary of the provided text
- `title` - Generate a concise title for the text
- `classify` - Classify text into one of the provided categories
- `split` - Split text into semantic chunks
- `tokens` - Tokenize text and optionally count tokens

#### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--text` | Text to process | - |
| `--file` | Read text from a file instead of --text | - |
| `--provider` | LLM provider (openai, anthropic, google, etc.) | - |
| `--model` | Model to use for the provider | - |
| `--temperature` | Temperature setting (0.0-1.0) | - |
| `--categories` | Comma-separated list of categories (for classify) | - |
| `--examples` | JSON array of {text, category} examples (for classify) | - |
| `--fallback-category` | Fallback category if classification fails | - |
| `--fallback-title` | Fallback title if generation fails | - |
| `--max-words` | Maximum words in title | 14 |
| `--strategy` | Summarization strategy (stuff, map_reduce, refine) | - |
| `--chunk-size` | Chunk size for splitting | 1000 |
| `--verbose` | Enable verbose output | false |
| `--output` | Output format (text, json) | text |
| `--save` | Save output to file | - |

#### Examples

```bash
# Summarize text
mix text summarize --text "Long article text..."

# Summarize from file with specific provider
mix text summarize --file article.txt --provider anthropic

# Generate title with custom max words
mix text title --text "Article content..." --max-words 10

# Classify text with categories
mix text classify --text "Tech news..." --categories "Technology,Business,Health"

# Classify with examples and fallback
mix text classify --file news.txt --categories "Tech,Business" \
  --examples '[{"text":"iPhone release","category":"Tech"}]' \
  --fallback-category "Other"

# Split text into chunks
mix text split --file document.txt --chunk-size 500

# Count tokens
mix text tokens --text "Sample text to tokenize" --output json
```

### `mix research`

Conducts comprehensive research on a topic using Mulberry's research capabilities.

#### Usage
```bash
mix research TOPIC [options]
```

#### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--strategy` | Research strategy: web, local, or hybrid | web |
| `--max-sources` | Maximum number of sources to analyze | 5 |
| `--depth` | Research depth 1-3, higher is more thorough | 1 |
| `--format` | Output format: text, markdown, or json | text |
| `--save` | Save results to specified file | - |
| `--verbose` | Show detailed progress information | false |
| `--search-paths` | Directories to search (local strategy only) | - |
| `--file-patterns` | File patterns to match (local strategy only) | - |
| `--domains` | Domains to include in web search | - |
| `--exclude-domains` | Domains to exclude from web search | - |
| `--content-length` | Detail level: short, medium, long, comprehensive | medium |
| `--search-module` | Search module to use (e.g., brave, reddit) | - |
| `--search-modules` | JSON array of search module configs for multi-source | - |

#### Examples

```bash
# Basic web research
mix research "quantum computing applications"

# Hybrid research with more sources
mix research "machine learning trends" --strategy hybrid --max-sources 10

# Local document research
mix research "project documentation" --strategy local \
  --search-paths ./docs --file-patterns "*.md,*.txt"

# Save results to markdown
mix research "renewable energy" --save results.md --format markdown

# Verbose mode with JSON output
mix research "AI safety" --verbose --format json --save research.json

# Web research with domain filtering
mix research "elixir programming" --domains "elixir-lang.org,hexdocs.pm" \
  --exclude-domains "reddit.com"

# Research using Reddit as search source
mix research "machine learning" --search-module reddit

# Multi-source research with Brave and Reddit
mix research "elixir tips" --search-modules '[
  {"module": "brave", "options": {}},
  {"module": "reddit", "options": {"sort": "top"}, "weight": 1.5}
]'
```

## Environment Variables

Several mix tasks require API keys to be set as environment variables:

- `DATAFORSEO_USERNAME` - Required for DataForSEO Business Listings functionality
- `DATAFORSEO_PASSWORD` - Required for DataForSEO Business Listings functionality
- `OPENAI_API_KEY` - Required for AI features (summarization, title generation, research)
- `BRAVE_API_KEY` - Required for Brave search functionality
- `SCRAPECREATORS_API_KEY` - Required for Google, Reddit, Facebook Ads, and YouTube search

## Best Practices

1. **API Keys**: Ensure all required environment variables are set before running tasks
2. **Rate Limits**: Be mindful of API rate limits when performing multiple searches
3. **Output Formats**: Use JSON format when integrating with other tools
4. **Saving Results**: Use the `--save` option to persist results for later analysis
5. **Verbose Mode**: Enable `--verbose` for debugging or understanding task progress

## Error Handling

All tasks will:
- Display clear error messages when required parameters are missing
- Exit with status code 1 on failure
- Provide helpful usage information when called incorrectly

## Integration Examples

### Combining Tasks

```bash
# Fetch a URL and then summarize its content
mix fetch_url https://example.com --show-text --save article.txt
mix text summarize --file article.txt

# Search for content and research a topic based on results
mix search "latest AI developments" --save results.json
mix research "AI developments 2024" --verbose

# Fetch business listings for multiple locations
mix business_listings -c restaurant -l "40.7128,-74.0060,5" -o nyc.json
mix business_listings -c restaurant -l "34.0522,-118.2437,5" -o la.json
```

### Scripting

```bash
#!/bin/bash
# Research multiple topics and save results

topics=("quantum computing" "renewable energy" "space exploration")

for topic in "${topics[@]}"; do
  mix research "$topic" --format markdown --save "research_${topic// /_}.md"
done
```

```bash
#!/bin/bash
# Fetch business listings for multiple cities

cities=(
  "New York:40.7128,-74.0060,10"
  "Los Angeles:34.0522,-118.2437,10"
  "Chicago:41.8781,-87.6298,10"
)

for city_data in "${cities[@]}"; do
  city_name="${city_data%%:*}"
  coords="${city_data#*:}"
  filename="${city_name// /_}_pizza.json"

  mix business_listings \
    -c pizza_restaurant \
    -l "$coords" \
    -f "rating.value,>,4.0" \
    -s "rating.value,desc" \
    -n 50 \
    -o "$filename"
done
```