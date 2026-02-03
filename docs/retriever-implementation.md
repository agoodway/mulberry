# Retriever System Implementation

This document provides technical implementation details for the Mulberry retriever system.

## Overview

The retriever system provides a unified interface for fetching web content using different strategies. It uses a behaviour-based architecture allowing multiple implementations with automatic fallback support.

## Core Module

### Mulberry.Retriever

The main entry point defining the behaviour and dispatch logic.

**Behaviour Callback:**
```elixir
@callback get(String.t(), Keyword.t()) :: {:ok, map()} | {:error, atom()}
```

**Dispatch Function:**
```elixir
@spec get(module() | [module()], String.t(), Keyword.t()) :: {:ok, map()} | {:error, atom()}
```

**Fallback Chain:**

When given a list of modules, tries each in order until one succeeds:

```elixir
Mulberry.Retriever.get([Req, Playwright, ScrapingBee], url)
# Tries Req first, falls back to Playwright on failure, then ScrapingBee
```

## Response Structure

### Mulberry.Retriever.Response

Standard response struct used by all retrievers:

```elixir
%Mulberry.Retriever.Response{
  status: :ok | :failed | :rate_limited,
  content: String.t() | map() | nil
}
```

**Default Responder:**

Converts response structs to ok/error tuples:
- `:ok` status -> `{:ok, response}`
- `:failed` status -> `{:error, response}`
- `:rate_limited` status -> `{:error, response}`

Custom responders can be passed via the `:responder` option.

## Implementations

### Mulberry.Retriever.Req

Simple HTTP client using the Req library.

**Use Cases:**
- Static HTML pages
- APIs returning JSON/HTML
- Fast, lightweight requests

**Options:**
- `:params` - Query parameters (map)
- `:headers` - HTTP headers (map)
- `:responder` - Custom response handler

**Implementation:**
```elixir
Req.get(url, headers: headers, params: params)
# Returns response with status < 400 as :ok
# Any error or 4xx/5xx status returns :failed
```

---

### Mulberry.Retriever.Playwright

Browser-based retriever using Playwright for JavaScript-heavy pages.

**Use Cases:**
- Single Page Applications (SPAs)
- JavaScript-rendered content
- Sites with bot detection
- Dynamic content loading

**Bot Evasion Features:**
- Randomized user agents (6 common browser strings)
- Randomized viewport sizes (5 common resolutions)
- Random delays between actions
- WebDriver property override
- Human-like scrolling behavior
- Mouse movement simulation

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `:browser` | `:chromium` | Browser type (`:chromium`, `:firefox`, `:webkit`) |
| `:headless` | `true` | Run without visible window |
| `:user_agent` | Random | Custom UA string |
| `:viewport` | Random | Map with `:width` and `:height` |
| `:stealth_mode` | `true` | Enable bot evasion features |
| `:delay_range` | `{100, 500}` | Min/max delay in ms |
| `:proxy` | `nil` | Proxy config map |
| `:locale` | `"en-US"` | Browser locale |
| `:timezone` | `"America/New_York"` | Timezone ID |
| `:wait_for_selector` | `"body"` | CSS selector to wait for |
| `:browser_args` | `[]` | Additional launch args |

**Proxy Configuration:**
```elixir
proxy: %{
  server: "http://proxy.example.com:8080",
  username: "user",
  password: "pass"
}
```

**Browser Args (Default):**
- `--disable-blink-features=AutomationControlled`
- `--disable-dev-shm-usage`
- `--no-sandbox`
- `--disable-setuid-sandbox`
- `--disable-web-security`
- `--disable-features=IsolateOrigins,site-per-process`

**Execution Flow:**
1. Launch browser with options
2. Create context with user agent, viewport, locale, timezone
3. Create page and inject stealth scripts
4. Navigate to URL (wait for `networkidle`)
5. Perform human-like actions (scrolling, mouse)
6. Wait for selector
7. Extract HTML via `inner_html()`
8. Close page and browser

---

### Mulberry.Retriever.ScrapingBee

Cloud-based scraping service via ScrapingBee API.

**Use Cases:**
- High-volume scraping
- IP rotation needs
- Captcha handling
- Geo-targeted requests

**Configuration:**

Requires API key via:
- Environment: `SCRAPING_BEE_API_KEY`
- Config: `:scraping_bee_api_key`

**Implementation:**
```elixir
url = "https://app.scrapingbee.com/api/v1/?api_key=#{api_key}&url=#{encoded_url}"
Req.get(url)
```

---

### Mulberry.Retriever.FacebookProfile

Specialized retriever for Facebook profile data via ScrapeCreators API.

**Configuration:**

Requires API key via:
- Environment: `SCRAPECREATORS_API_KEY`
- Config: `:scrapecreators_api_key`

**API Endpoint:** `https://api.scrapecreators.com/v1/facebook/profile`

**Response Data:**

Transforms API response to normalized structure:

```elixir
%{
  id: String.t(),
  name: String.t(),
  url: String.t(),
  gender: String.t(),
  cover_photo: String.t(),
  profile_photo: String.t(),
  is_business_page_active: boolean(),
  page_intro: String.t(),
  category: String.t(),
  address: String.t(),
  email: String.t(),
  links: [String.t()],
  phone: String.t(),
  website: String.t(),
  services: String.t(),
  price_range: String.t(),
  rating: float(),
  rating_count: integer(),
  like_count: integer(),
  follower_count: integer(),
  ad_library: map(),
  creation_date: String.t()
}
```

---

### Mulberry.Retriever.GoogleAd

Specialized retriever for Google Ad Transparency data via ScrapeCreators API.

**Configuration:**

Requires API key via:
- Environment: `SCRAPECREATORS_API_KEY`
- Config: `:scrapecreators_api_key`

**API Endpoint:** `https://api.scrapecreators.com/v1/google/ad`

**Rate Limiting:**

Returns `:rate_limited` status on 429 response (vs `:failed` for other errors).

**Response Data:**

Returns raw API response containing:
- `variations` - List of ad variations
- `regionStats` - Regional impression statistics
- `overallImpressions` - Overall impression range

## Usage Examples

### Basic HTTP Request
```elixir
{:ok, response} = Mulberry.Retriever.get(Mulberry.Retriever.Req, "https://example.com")
html = response.content
```

### JavaScript-Heavy Site
```elixir
{:ok, response} = Mulberry.Retriever.get(
  Mulberry.Retriever.Playwright,
  "https://spa-example.com",
  wait_for_selector: "#app-loaded",
  stealth_mode: true
)
```

### Fallback Chain
```elixir
{:ok, response} = Mulberry.Retriever.get(
  [Mulberry.Retriever.Req, Mulberry.Retriever.Playwright],
  url
)
# Tries simple HTTP first, falls back to browser if needed
```

### With Custom Headers
```elixir
{:ok, response} = Mulberry.Retriever.get(
  Mulberry.Retriever.Req,
  url,
  headers: %{"Authorization" => "Bearer token", "Accept" => "application/json"}
)
```

### ScrapingBee with Proxy Rotation
```elixir
{:ok, response} = Mulberry.Retriever.get(
  Mulberry.Retriever.ScrapingBee,
  "https://protected-site.com"
)
# ScrapingBee handles proxy rotation automatically
```

### Custom Response Handler
```elixir
custom_responder = fn
  %{status: :ok, content: content} -> {:ok, Jason.decode!(content)}
  %{status: _} -> {:error, :fetch_failed}
end

{:ok, parsed_json} = Mulberry.Retriever.get(
  Mulberry.Retriever.Req,
  "https://api.example.com/data",
  responder: custom_responder
)
```

## Integration with Crawler

The crawler system uses retrievers via the `:retriever` option:

```elixir
# Default (Req)
Mulberry.Crawler.crawl_website(url)

# Playwright for JS sites
Mulberry.Crawler.crawl_website(url, retriever: Mulberry.Retriever.Playwright)

# Fallback chain
Mulberry.Crawler.crawl_website(url, retriever: [
  Mulberry.Retriever.Req,
  Mulberry.Retriever.Playwright
])
```

## Error Handling

All retrievers follow consistent error patterns:

| Scenario | Response Status |
|----------|-----------------|
| Successful fetch | `:ok` |
| HTTP 4xx/5xx | `:failed` |
| Network error | `:failed` |
| Rate limited (429) | `:rate_limited` |
| Missing API key | `:failed` |
| Timeout | `:failed` |

Errors are logged via `Logger.error/1` with module context.

## Adding Custom Retrievers

Implement the behaviour:

```elixir
defmodule MyApp.CustomRetriever do
  @behaviour Mulberry.Retriever

  @impl true
  def get(url, opts \\ []) do
    responder = Keyword.get(opts, :responder, &Mulberry.Retriever.Response.default_responder/1)

    case fetch_somehow(url, opts) do
      {:ok, content} ->
        %Mulberry.Retriever.Response{status: :ok, content: content}
        |> responder.()

      {:error, _reason} ->
        %Mulberry.Retriever.Response{status: :failed, content: nil}
        |> responder.()
    end
  end
end

# Use with Mulberry
Mulberry.Retriever.get(MyApp.CustomRetriever, url)
```
