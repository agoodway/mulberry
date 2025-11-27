# DataForSEO Programmatic API Guide

This document provides comprehensive information about using DataForSEO tasks programmatically in your Elixir applications.

## Overview

The DataForSEO system provides a supervised, callback-based architecture for running API tasks. It handles:

- **Async Tasks** - Polling-based tasks like Google Reviews and Questions (creates task → polls → fetches results)
- **Live Tasks** - Instant results like Business Listings (single API call)
- **Automatic Retries** - Up to 3 retries on transient errors
- **Task Supervision** - All tasks are supervised and automatically cleaned up
- **Type-Safe Results** - Structured schemas with helper functions

### Architecture Components

1. **DataForSEO.Supervisor** - Main entry point for starting and managing tasks
2. **DataForSEO.TaskManager** - GenServer managing individual task lifecycle
3. **DataForSEO.TaskRegistry** - ETS registry tracking active tasks
4. **Task Modules** - GoogleQuestions, GoogleReviews, BusinessListings, etc.
5. **Schema Modules** - Typed result structures with helper functions

## Getting Started

### Basic Usage Pattern

```elixir
# 1. Start a task with callback
{:ok, pid} = DataForSEO.Supervisor.start_task(
  DataForSEO.Tasks.GoogleQuestions,
  %{cid: "10179360708466590899", depth: 50},
  callback: fn
    {:ok, result} -> IO.inspect(result)
    {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
  end
)

# 2. System handles everything (creating, polling, fetching, retrying)
# 3. Callback is invoked when done
```

### Environment Variables

Required for all DataForSEO tasks:
```bash
export DATAFORSEO_USERNAME="your_username"
export DATAFORSEO_PASSWORD="your_password"
```

Get credentials at: https://app.dataforseo.com/api-access

## DataForSEO.Supervisor API

### Starting Tasks

```elixir
@spec start_task(module(), map(), keyword()) :: {:ok, pid()} | {:error, term()}
```

**Parameters:**
- `task_module` - Task implementation module
- `task_params` - Map of parameters for the task
- `opts` - Options (optional)

**Options:**
- `:callback` - Function called with results: `fn {:ok, result} | {:error, reason} -> ... end`
- `:poll_interval_ms` - Milliseconds between polls (default: 5000)
- `:timeout_ms` - Total timeout in milliseconds (default: 300000 / 5 minutes)
- `:task_id` - Custom task ID (auto-generated if not provided)

**Example:**
```elixir
{:ok, pid} = DataForSEO.Supervisor.start_task(
  DataForSEO.Tasks.GoogleQuestions,
  %{cid: "12345", depth: 20},
  callback: &handle_result/1,
  timeout_ms: 600_000,
  task_id: "custom_task_123"
)
```

### Managing Tasks

```elixir
# Stop a task
@spec stop_task(String.t()) :: :ok | {:error, :not_found}
DataForSEO.Supervisor.stop_task(task_id)

# List all active tasks
@spec list_tasks() :: list(map())
tasks = DataForSEO.Supervisor.list_tasks()
# Returns: [%{task_id: "dfs_...", pid: #PID<...>, module: GoogleReviews, alive: true, status: :monitoring}]

# Get system statistics
@spec get_stats() :: map()
stats = DataForSEO.Supervisor.get_stats()
# Returns: %{total_tasks: 10, alive_tasks: 8, dead_tasks: 2, by_module: %{GoogleReviews => 5}}
```

### Monitoring Task Status

```elixir
{:ok, pid} = DataForSEO.Supervisor.start_task(task_module, params)

# Get detailed status
{:ok, status} = DataForSEO.TaskManager.get_status(pid)

# Status structure:
%{
  status: :monitoring | :fetching | :completed | :failed,
  task_ids: ["task123"],
  results: [],
  error: nil,
  retry_count: 0,
  created_at: ~U[2025-01-15 10:00:00Z],
  updated_at: ~U[2025-01-15 10:00:05Z]
}
```

## Task Reference

### GoogleQuestions

Fetch questions and answers from Google My Business.

**Module:** `DataForSEO.Tasks.GoogleQuestions`

**Type:** Async (polling required)

**Parameters:**

Business identifier (choose one):
- `:keyword` - Business name (max 700 chars)
- `:cid` - Google Customer ID (recommended)
- `:place_id` - Google Place ID

Location (required if using keyword):
- `:location_name` - Full location name (e.g., "Los Angeles,California,United States")
- `:location_code` - Numeric location code
- `:location_coordinate` - "latitude,longitude,radius" format

Optional:
- `:language_code` - Language code (default: "en")
- `:depth` - Questions to fetch (default: 20, max: 700)
- `:priority` - 1 (normal) or 2 (high, extra cost)
- `:tag` - User identifier (max 255 chars)

**Basic Example:**

```elixir
{:ok, pid} = DataForSEO.Supervisor.start_task(
  DataForSEO.Tasks.GoogleQuestions,
  %{
    cid: "10179360708466590899",
    language_code: "en",
    depth: 50
  },
  callback: fn
    {:ok, result} ->
      IO.puts("Total questions: #{GoogleQuestionsResult.total_question_count(result)}")
      IO.puts("Answered: #{GoogleQuestionsResult.answered_question_count(result)}")
      IO.puts("Unanswered: #{GoogleQuestionsResult.unanswered_question_count(result)}")

    {:error, reason} ->
      IO.puts("Failed: #{inspect(reason)}")
  end
)
```

**Using Keyword with Location:**

```elixir
{:ok, pid} = DataForSEO.Supervisor.start_task(
  DataForSEO.Tasks.GoogleQuestions,
  %{
    keyword: "Pike Place Starbucks",
    location_name: "Seattle,Washington,United States",
    language_code: "en",
    depth: 30
  },
  callback: &process_questions/1
)
```

**Result Type:** `DataForSEO.Schemas.GoogleQuestionsResult`

```elixir
%GoogleQuestionsResult{
  questions_with_answers: [GoogleQuestion.t()],
  questions_without_answers: [GoogleQuestion.t()],
  metadata: %{
    keyword: "Pike Place Starbucks",
    cid: "10938722528802138001",
    location_code: 1027744,
    language_code: "en",
    items_count: 28,
    check_url: "https://...",
    datetime: "2025-11-26 21:17:37 +00:00"
  }
}
```

**Helper Functions:**

```elixir
alias DataForSEO.Schemas.GoogleQuestionsResult

GoogleQuestionsResult.total_question_count(result)      # => 28
GoogleQuestionsResult.all_questions(result)             # => [all questions]
GoogleQuestionsResult.answered_question_count(result)   # => 20
GoogleQuestionsResult.unanswered_question_count(result) # => 8

# Access specific questions
result.questions_with_answers      # Questions that have answers
result.questions_without_answers   # Unanswered questions

# Each question:
question = hd(result.questions_with_answers)
GoogleQuestion.answer_count(question)   # => 5
GoogleQuestion.has_answers?(question)   # => true
```

### GoogleReviews

Fetch Google Maps reviews for a business.

**Module:** `DataForSEO.Tasks.GoogleReviews`

**Type:** Async (polling required)

**Parameters:**

Business identifier (choose one):
- `:keyword` - Business name
- `:cid` - Google Customer ID (recommended)
- `:place_id` - Google Place ID

Location (required if using keyword):
- `:location_name`, `:location_code`, or `:location_coordinate`

Optional:
- `:language_code` - Language code (default: "en")
- `:depth` - Reviews to fetch (default: 10, max: 4490)
- `:sort_by` - "newest", "highest_rating", "lowest_rating", "relevant"
- `:priority` - 1 or 2
- `:tag` - User identifier

**Example:**

```elixir
{:ok, pid} = DataForSEO.Supervisor.start_task(
  DataForSEO.Tasks.GoogleReviews,
  %{
    cid: "10179360708466590899",
    language_code: "en",
    depth: 100,
    sort_by: "newest"
  },
  callback: fn {:ok, result} ->
    IO.puts("Business: #{result.title}")
    IO.puts("Rating: #{result.rating["value"]}/5 (#{result.reviews_count} reviews)")

    # Process reviews
    Enum.each(result.reviews, fn review ->
      stars = review.rating["value"]
      IO.puts("#{review.profile_name}: #{stars} stars")
      IO.puts("  #{String.slice(review.review_text, 0..100)}...")

      # Check for owner response
      if review.owner_answer do
        IO.puts("  Owner: #{review.owner_answer}")
      end
    end)
  end
)
```

**Result Type:** `DataForSEO.Schemas.GoogleReviewsResult`

```elixir
%GoogleReviewsResult{
  keyword: "Business Name",
  cid: "10179360708466590899",
  place_id: "ChIJ...",
  title: "Business Name",
  sub_title: "Address",
  rating: %{"value" => 4.5, "votes_count" => 150},
  reviews_count: 150,
  reviews: [GoogleReview.t()],
  check_url: "https://..."
}

# Each review:
%GoogleReview{
  review_id: "...",
  review_text: "Great service!",
  rating: %{"value" => 5},
  profile_name: "John Doe",
  profile_image_url: "https://...",
  timestamp: "2023-11-26 21:17:36 +00:00",
  owner_answer: "Thank you!",  # May be nil
  ...
}
```

### ExtendedGoogleReviews

Fetch multi-platform reviews (Google + TripAdvisor, Yelp, etc.).

**Module:** `DataForSEO.Tasks.ExtendedGoogleReviews`

**Type:** Async (polling required)

**Parameters:** Same as GoogleReviews, but:
- Max depth: 1000 (vs 4490)
- Default depth: 20 (vs 10)
- Includes reviews from multiple platforms

**Example:**

```elixir
{:ok, pid} = DataForSEO.Supervisor.start_task(
  DataForSEO.Tasks.ExtendedGoogleReviews,
  %{
    cid: "10179360708466590899",
    depth: 100,
    sort_by: "newest"
  },
  callback: fn {:ok, result} ->
    # Same result structure as GoogleReviews
    # but may include reviews from other platforms
    analyze_extended_reviews(result)
  end
)
```

### BusinessListings

Search for businesses on Google Maps.

**Module:** `DataForSEO.Tasks.BusinessListings`

**Type:** Live (instant results, no polling)

**Parameters:**

Search criteria:
- `:categories` - List of category IDs, e.g., `["pizza_restaurant"]` (max 10)
- `:location_coordinate` - "latitude,longitude,radius_km" (radius: 1-100000)
- `:title` - Business name search (max 200 chars)
- `:description` - Description search (max 200 chars)
- `:is_claimed` - Boolean for verified businesses only

Filtering:
- `:filters` - List of filters: `[["field", "operator", value]]` (max 8)
  - Operators: `"<"`, `"<="`, `">"`, `">="`, `"="`, `"!="`, `"like"`, `"not_like"`, `"regex"`, `"not_regex"`
- `:order_by` - Sort rules: `[["field", "asc"|"desc"]]` (max 3)

Pagination:
- `:limit` - Max results (default: 100, max: 1000)
- `:offset` - Offset for pagination

**Example:**

```elixir
{:ok, pid} = DataForSEO.Supervisor.start_task(
  DataForSEO.Tasks.BusinessListings,
  %{
    categories: ["pizza_restaurant"],
    location_coordinate: "40.7128,-74.0060,10",  # NYC, 10km
    filters: [
      ["rating.value", ">", 4.0],
      ["rating.votes_count", ">", 50],
      ["is_claimed", "=", true]
    ],
    order_by: [["rating.value", "desc"]],
    limit: 100
  },
  callback: fn {:ok, result} ->
    IO.puts("Found #{result.total_count} businesses")

    Enum.each(result.items, fn business ->
      IO.puts("""
      #{business.title}
        Category: #{business.category}
        Rating: #{business.rating["value"]} (#{business.rating["votes_count"]} reviews)
        CID: #{business.cid}
        Address: #{business.address}
      """)
    end)
  end
)

# Note: Business Listings returns results immediately (live endpoint)
```

**Result Type:** `DataForSEO.Schemas.BusinessListingsResult`

```elixir
%BusinessListingsResult{
  total_count: 36,
  items: [BusinessListing.t()]
}

# Each business listing:
%BusinessListing{
  unique_id: "12345678901234567890",  # Auto-generated from CID
  type: "business_listing",
  title: "Joe's Pizza",
  description: "Best pizza in town",
  category: "Pizza restaurant",
  category_ids: ["pizza_restaurant"],
  address: "123 Main St, New York, NY 10001",
  phone: "+1-555-0123",
  url: "https://maps.google.com/...",
  cid: "12345678901234567890",
  place_id: "ChIJ...",
  latitude: 40.7128,
  longitude: -74.0060,
  rating: %{"value" => 4.5, "votes_count" => 150},
  is_claimed: true,
  work_time: %{"Monday" => "09:00-22:00", ...},
  ...
}
```

**BusinessListing Helper Functions:**

```elixir
alias DataForSEO.Schemas.BusinessListing

# Fetch reviews for a business
{:ok, pid} = BusinessListing.fetch_reviews(
  business,
  depth: 100,
  sort_by: "newest",
  callback: fn {:ok, reviews} ->
    IO.inspect(reviews.reviews_count)
  end
)

# Fetch extended reviews (multi-platform)
{:ok, pid} = BusinessListing.fetch_extended_reviews(
  business,
  depth: 100,
  callback: &handle_reviews/1
)

# Unique ID generation (automatically included in results)
id = BusinessListing.generate_id(business)
listing_with_id = BusinessListing.with_id(business)
```

## Callback Patterns

### Basic Callback

```elixir
callback = fn
  {:ok, result} ->
    # Handle success
    process_result(result)

  {:error, reason} ->
    # Handle error
    Logger.error("Task failed: #{inspect(reason)}")
end

{:ok, pid} = DataForSEO.Supervisor.start_task(
  task_module,
  params,
  callback: callback
)
```

### Process Communication Pattern

```elixir
defmodule MyApp.DataFetcher do
  def fetch_questions(cid) do
    parent = self()
    ref = make_ref()

    callback = fn result ->
      send(parent, {ref, result})
    end

    {:ok, pid} = DataForSEO.Supervisor.start_task(
      DataForSEO.Tasks.GoogleQuestions,
      %{cid: cid},
      callback: callback
    )

    receive do
      {^ref, {:ok, result}} ->
        {:ok, result}
      {^ref, {:error, reason}} ->
        {:error, reason}
    after
      60_000 -> {:error, :timeout}
    end
  end
end
```

### GenServer Integration

```elixir
defmodule MyApp.ReviewMonitor do
  use GenServer

  def start_link(business_cid) do
    GenServer.start_link(__MODULE__, business_cid, name: __MODULE__)
  end

  @impl true
  def init(business_cid) do
    # Start review fetch on init
    {:ok, pid} = DataForSEO.Supervisor.start_task(
      DataForSEO.Tasks.GoogleReviews,
      %{cid: business_cid, depth: 100},
      callback: fn result ->
        send(self(), {:reviews_ready, result})
      end
    )

    {:ok, %{cid: business_cid, task_pid: pid, reviews: nil}}
  end

  @impl true
  def handle_info({:reviews_ready, {:ok, result}}, state) do
    # Store reviews
    new_state = %{state | reviews: result}

    # Process reviews
    analyze_reviews(result)

    {:noreply, new_state}
  end

  def handle_info({:reviews_ready, {:error, reason}}, state) do
    Logger.error("Failed to fetch reviews: #{inspect(reason)}")
    {:noreply, state}
  end

  defp analyze_reviews(result) do
    # Your analysis logic
    positive = Enum.count(result.reviews, &(&1.rating["value"] >= 4))
    IO.puts("Positive reviews: #{positive}")
  end
end
```

### Pipeline Pattern

```elixir
defmodule MyApp.BusinessAnalyzer do
  def analyze_and_store(search_params) do
    # Step 1: Find businesses
    {:ok, _pid} = DataForSEO.Supervisor.start_task(
      DataForSEO.Tasks.BusinessListings,
      search_params,
      callback: &process_businesses/1
    )
  end

  defp process_businesses({:ok, result}) do
    result.items
    |> Enum.take(10)  # Top 10
    |> Enum.each(&fetch_business_data/1)
  end

  defp fetch_business_data(business) do
    # Fetch both reviews and Q&A in parallel
    {:ok, _} = BusinessListing.fetch_reviews(
      business,
      depth: 50,
      callback: &store_reviews(business.cid, &1)
    )

    {:ok, _} = DataForSEO.Supervisor.start_task(
      DataForSEO.Tasks.GoogleQuestions,
      %{cid: business.cid, depth: 30},
      callback: &store_questions(business.cid, &1)
    )
  end

  defp store_reviews(cid, {:ok, result}) do
    MyApp.Database.insert_reviews(cid, result.reviews)
  end

  defp store_questions(cid, {:ok, result}) do
    all_questions = GoogleQuestionsResult.all_questions(result)
    MyApp.Database.insert_questions(cid, all_questions)
  end
end
```

## Error Handling

### Validation Errors

Tasks validate parameters before starting:

```elixir
# Missing required parameter
{:error, {:invalid_params, "One of keyword, cid, or place_id is required"}}

# Invalid depth
{:error, {:invalid_params, "depth must be between 1 and 700"}}

# Keyword without location
{:error, {:invalid_params, "Location parameter required when using keyword"}}

# Invalid sort_by
{:error, {:invalid_params, "sort_by must be one of: newest, highest_rating, lowest_rating, relevant"}}
```

### Runtime Errors

Errors returned via callback:

```elixir
# API errors
{:error, {:api_error, 500, "Server Error"}}
{:error, {:api_error, 400, "Bad Request"}}

# Task creation failed
{:error, {:task_creation_failed, "Invalid Field: 'keyword'."}}

# Task failed during execution
{:error, {:task_failed, "No Search Results."}}

# Timeout
{:error, :timeout}

# No results
{:error, {:no_results, "Task completed but no results found"}}

# Invalid response
{:error, {:invalid_response, "Expected tasks array in response"}}

# Missing credentials
{:error, :missing_credentials}
```

### Automatic Retry Logic

TaskManager automatically retries on transient errors:
- Max retries: 3
- Retries on: 5xx errors, network errors, timeouts
- Exponential backoff on certain errors (503)
- No retry on: 4xx validation errors, missing credentials

### Error Recovery Pattern

```elixir
defmodule MyApp.RobustFetcher do
  def fetch_with_custom_retry(task_module, params, max_attempts \\ 3) do
    attempt_fetch(task_module, params, 1, max_attempts)
  end

  defp attempt_fetch(task_module, params, attempt, max_attempts) do
    ref = make_ref()
    parent = self()

    callback = fn result ->
      send(parent, {ref, result})
    end

    {:ok, _pid} = DataForSEO.Supervisor.start_task(
      task_module,
      params,
      callback: callback,
      timeout_ms: 600_000
    )

    receive do
      {^ref, {:ok, result}} ->
        {:ok, result}

      {^ref, {:error, reason}} when attempt < max_attempts ->
        Logger.warn("Attempt #{attempt}/#{max_attempts} failed: #{inspect(reason)}")

        # Exponential backoff
        sleep_ms = :math.pow(2, attempt) * 1000
        Process.sleep(trunc(sleep_ms))

        attempt_fetch(task_module, params, attempt + 1, max_attempts)

      {^ref, {:error, reason}} ->
        {:error, reason}
    after
      650_000 ->
        {:error, :timeout}
    end
  end
end
```

## Advanced Examples

### Example 1: Batch Processing

```elixir
defmodule MyApp.BatchReviewFetcher do
  def fetch_reviews_for_businesses(business_cids) do
    # Track all tasks
    task_tracker = start_tracker(length(business_cids))

    # Start all tasks
    Enum.each(business_cids, fn cid ->
      start_review_task(cid, task_tracker)
    end)

    # Wait for all to complete
    wait_for_batch(task_tracker)
  end

  defp start_tracker(total) do
    {:ok, agent} = Agent.start_link(fn ->
      %{total: total, completed: 0, results: %{}, errors: %{}}
    end)
    agent
  end

  defp start_review_task(cid, tracker) do
    callback = fn result ->
      update_tracker(tracker, cid, result)
    end

    DataForSEO.Supervisor.start_task(
      DataForSEO.Tasks.GoogleReviews,
      %{cid: cid, depth: 50},
      callback: callback,
      task_id: "reviews_#{cid}"
    )
  end

  defp update_tracker(tracker, cid, result) do
    Agent.update(tracker, fn state ->
      new_state = %{state | completed: state.completed + 1}

      case result do
        {:ok, data} ->
          %{new_state | results: Map.put(state.results, cid, data)}
        {:error, reason} ->
          %{new_state | errors: Map.put(state.errors, cid, reason)}
      end
    end)
  end

  defp wait_for_batch(tracker) do
    Stream.interval(1000)
    |> Enum.find_value(fn _ ->
      state = Agent.get(tracker, & &1)

      if state.completed == state.total do
        Agent.stop(tracker)
        {:ok, state.results, state.errors}
      end
    end)
  end
end

# Usage:
{:ok, results, errors} = MyApp.BatchReviewFetcher.fetch_reviews_for_businesses([
  "10179360708466590899",
  "10938722528802138001",
  "12345678901234567890"
])

IO.puts("Success: #{map_size(results)}, Errors: #{map_size(errors)}")
```

### Example 2: Complete Business Intelligence Pipeline

```elixir
defmodule MyApp.BusinessIntelligence do
  alias DataForSEO.Tasks.{BusinessListings, GoogleReviews, GoogleQuestions}
  alias DataForSEO.Schemas.{BusinessListing, GoogleQuestionsResult}

  def analyze_market(category, location, radius_km) do
    search_params = %{
      categories: [category],
      location_coordinate: "#{location},#{radius_km}",
      filters: [["rating.value", ">=", 3.5]],
      order_by: [["rating.value", "desc"]],
      limit: 50
    }

    {:ok, _pid} = DataForSEO.Supervisor.start_task(
      BusinessListings,
      search_params,
      callback: &analyze_businesses/1
    )
  end

  defp analyze_businesses({:ok, result}) do
    IO.puts("Analyzing #{length(result.items)} businesses...")

    Enum.each(result.items, fn business ->
      # Fetch comprehensive data for each business
      fetch_comprehensive_data(business)
    end)
  end

  defp fetch_comprehensive_data(business) do
    ref = make_ref()
    parent = self()

    # Start both tasks in parallel
    {:ok, _} = BusinessListing.fetch_reviews(
      business,
      depth: 100,
      callback: fn result ->
        send(parent, {ref, :reviews, result})
      end
    )

    {:ok, _} = DataForSEO.Supervisor.start_task(
      GoogleQuestions,
      %{cid: business.cid, depth: 50},
      callback: fn result ->
        send(parent, {ref, :questions, result})
      end
    )

    # Collect both results
    collect_results(business, ref, 2)
  end

  defp collect_results(business, ref, remaining, acc \\ %{}) do
    if remaining == 0 do
      finalize_analysis(business, acc)
    else
      receive do
        {^ref, :reviews, {:ok, reviews}} ->
          collect_results(business, ref, remaining - 1, Map.put(acc, :reviews, reviews))

        {^ref, :questions, {:ok, questions}} ->
          collect_results(business, ref, remaining - 1, Map.put(acc, :questions, questions))

        {^ref, _type, {:error, reason}} ->
          Logger.warn("Partial failure: #{inspect(reason)}")
          collect_results(business, ref, remaining - 1, acc)
      after
        120_000 ->
          Logger.error("Timeout collecting results for #{business.title}")
      end
    end
  end

  defp finalize_analysis(business, data) do
    analysis = %{
      business_name: business.title,
      cid: business.cid,
      overall_rating: business.rating["value"],
      total_reviews: Map.get(data, :reviews) |> then(& &1 && &1.reviews_count),
      total_questions: Map.get(data, :questions) |> then(& &1 && GoogleQuestionsResult.total_question_count(&1)),
      unanswered_questions: Map.get(data, :questions) |> then(& &1 && GoogleQuestionsResult.unanswered_question_count(&1))
    }

    MyApp.Database.store_analysis(business.cid, analysis)
    IO.inspect(analysis, label: "Analysis Complete")
  end
end
```

### Example 3: Real-Time Monitoring

```elixir
defmodule MyApp.CompetitorMonitor do
  use GenServer

  def start_link(competitor_cids) do
    GenServer.start_link(__MODULE__, competitor_cids, name: __MODULE__)
  end

  @impl true
  def init(competitor_cids) do
    # Schedule periodic checks
    schedule_check()

    state = %{
      competitors: competitor_cids,
      last_check: nil,
      data: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_info(:check_competitors, state) do
    # Check all competitors
    Enum.each(state.competitors, &check_competitor/1)

    # Schedule next check (daily)
    schedule_check()

    {:noreply, %{state | last_check: DateTime.utc_now()}}
  end

  @impl true
  def handle_info({:competitor_data, cid, data}, state) do
    # Store data and check for changes
    old_data = Map.get(state.data, cid)

    if data_changed?(old_data, data) do
      send_alert(cid, old_data, data)
    end

    new_state = put_in(state.data[cid], data)
    {:noreply, new_state}
  end

  defp schedule_check do
    # Check every 24 hours
    Process.send_after(self(), :check_competitors, 24 * 60 * 60 * 1000)
  end

  defp check_competitor(cid) do
    parent = self()

    # Fetch latest reviews
    DataForSEO.Supervisor.start_task(
      DataForSEO.Tasks.GoogleReviews,
      %{cid: cid, depth: 20, sort_by: "newest"},
      callback: fn {:ok, result} ->
        send(parent, {:competitor_data, cid, extract_metrics(result)})
      end
    )
  end

  defp extract_metrics(result) do
    %{
      rating: result.rating["value"],
      total_reviews: result.reviews_count,
      recent_reviews: length(result.reviews),
      avg_recent_rating: avg_rating(result.reviews),
      checked_at: DateTime.utc_now()
    }
  end

  defp avg_rating(reviews) do
    if length(reviews) > 0 do
      sum = Enum.sum(Enum.map(reviews, & &1.rating["value"]))
      Float.round(sum / length(reviews), 2)
    else
      0
    end
  end

  defp data_changed?(nil, _new), do: true
  defp data_changed?(old, new) do
    # Significant change in rating or review count
    abs(old.rating - new.rating) > 0.2 or
    abs(old.total_reviews - new.total_reviews) > 10
  end

  defp send_alert(cid, old, new) do
    IO.puts("""
    ALERT: Competitor #{cid} data changed!
      Rating: #{old.rating} → #{new.rating}
      Reviews: #{old.total_reviews} → #{new.total_reviews}
    """)
  end
end
```

## Configuration

### Application Config

```elixir
# config/config.exs
config :mulberry, :dataforseo,
  # Authentication (can also use env vars)
  username: System.get_env("DATAFORSEO_USERNAME"),
  password: System.get_env("DATAFORSEO_PASSWORD"),

  # Task defaults
  poll_interval_ms: 5_000,      # Check every 5 seconds
  timeout_ms: 300_000,           # 5 minute timeout

  # Retry configuration (built-in to Client)
  max_retries: 3,
  base_retry_delay_ms: 1_000
```

### Per-Task Configuration

```elixir
# Override defaults for specific tasks
{:ok, pid} = DataForSEO.Supervisor.start_task(
  task_module,
  params,
  poll_interval_ms: 10_000,     # Check every 10 seconds
  timeout_ms: 600_000            # 10 minute timeout
)
```

### BusinessListing ID Strategy

```elixir
# config/config.exs
config :mulberry, DataForSEO.Schemas.BusinessListing,
  id_strategy: :cid,              # Options: :cid, :place_id, :composite_hash
  composite_fields: [:cid, :place_id],
  id_prefix: nil                  # Optional prefix (e.g., "bl_")
```

## Testing

### Unit Testing with Mimic

```elixir
defmodule MyApp.DataFetcherTest do
  use ExUnit.Case, async: false
  use Mimic

  alias DataForSEO.{Supervisor, Client}

  setup :set_mimic_global

  setup do
    # Mock API responses
    stub(Client, :create_task, fn _type, _payload ->
      {:ok, %{"tasks" => [%{"id" => "task123", "status_code" => 20_100}]}}
    end)

    stub(Client, :check_ready_tasks, fn _type ->
      {:ok, %{"tasks" => [
        %{"result_count" => 1, "result" => [%{"id" => "task123"}]}
      ]}}
    end)

    stub(Client, :fetch_task_results, fn _type, _id, _endpoint ->
      {:ok, %{
        "tasks" => [%{
          "result" => [%{
            "keyword" => "Test",
            "items" => [],
            "items_without_answers" => []
          }]
        }]
      }}
    end)

    :ok
  end

  test "fetches questions successfully" do
    ref = make_ref()
    test_pid = self()

    callback = fn result ->
      send(test_pid, {ref, result})
    end

    {:ok, pid} = Supervisor.start_task(
      DataForSEO.Tasks.GoogleQuestions,
      %{cid: "12345"},
      callback: callback
    )

    assert Process.alive?(pid)

    # Should receive callback
    assert_receive {^ref, {:ok, result}}, 30_000
    assert %DataForSEO.Schemas.GoogleQuestionsResult{} = result
  end
end
```

### Integration Testing

```elixir
defmodule MyApp.GoogleQuestionsIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag timeout: 120_000

  # Only run if credentials are set
  @tag :skip_without_credentials
  test "fetches real questions from API" do
    ref = make_ref()
    test_pid = self()

    {:ok, _pid} = DataForSEO.Supervisor.start_task(
      DataForSEO.Tasks.GoogleQuestions,
      %{
        keyword: "Pike Place Starbucks",
        location_name: "Seattle,Washington,United States",
        depth: 10
      },
      callback: fn result ->
        send(test_pid, {ref, result})
      end
    )

    assert_receive {^ref, {:ok, result}}, 120_000
    assert result.metadata.keyword == "Pike Place Starbucks"
    # May have 0 or more questions depending on actual data
  end
end
```

## Task Lifecycle

### State Transitions

```
:initializing
  ↓ (params validated, task created)
:monitoring
  ↓ (task ready, results available)
:fetching
  ↓ (results retrieved)
:completed (callback invoked with {:ok, result})

OR

:failed (callback invoked with {:error, reason})
```

### Monitoring Example

```elixir
{:ok, pid} = DataForSEO.Supervisor.start_task(task_module, params)

# Check status periodically
Stream.repeatedly(fn ->
  case DataForSEO.TaskManager.get_status(pid) do
    {:ok, status} ->
      IO.puts("Status: #{status.status}, Tasks: #{length(status.task_ids)}")
      status
    {:error, _} ->
      :dead
  end
end)
|> Stream.take_while(&(&1 != :dead && &1.status != :completed))
|> Enum.to_list()
```

## Best Practices

### 1. Use CID for Stable Identifiers

```elixir
# ✅ Preferred - CID is most stable
%{cid: "10179360708466590899"}

# ⚠️  Use with caution - Place IDs can become obsolete
%{place_id: "ChIJ..."}

# ⚠️  Requires location - may match wrong business
%{keyword: "Starbucks", location_name: "Seattle,Washington,United States"}
```

### 2. Handle Callbacks Asynchronously

```elixir
# ✅ Good - Quick callback, spawn work
callback = fn result ->
  Task.start(fn -> heavy_processing(result) end)
end

# ❌ Bad - Blocks callback
callback = fn result ->
  # Don't do heavy work in callback
  heavy_processing(result)
end
```

### 3. Set Appropriate Timeouts

```elixir
# ✅ Good - Longer timeout for large requests
{:ok, pid} = DataForSEO.Supervisor.start_task(
  GoogleReviews,
  %{cid: cid, depth: 4490},  # Max depth
  timeout_ms: 600_000          # 10 minutes
)

# ❌ Bad - Default timeout may be too short
{:ok, pid} = DataForSEO.Supervisor.start_task(
  GoogleReviews,
  %{cid: cid, depth: 4490}
  # Uses default 5 minute timeout - might not be enough
)
```

### 4. Use Helper Functions

```elixir
# ✅ Good - Use schema helpers
total = GoogleQuestionsResult.total_question_count(result)
answered = GoogleQuestionsResult.answered_question_count(result)

# ❌ Bad - Manual calculation
total = length(result.questions_with_answers) + length(result.questions_without_answers)
```

### 5. Clean Up Tasks

```elixir
# Tasks auto-cleanup on completion, but you can stop early
task_id = "my_custom_task"

{:ok, pid} = DataForSEO.Supervisor.start_task(
  task_module,
  params,
  task_id: task_id
)

# If you need to cancel
DataForSEO.Supervisor.stop_task(task_id)
# or
DataForSEO.TaskManager.cancel(pid)
```

## Common Patterns

### Pattern: Fetch → Process → Store

```elixir
defmodule MyApp.DataPipeline do
  def fetch_and_store(cid) do
    DataForSEO.Supervisor.start_task(
      DataForSEO.Tasks.GoogleReviews,
      %{cid: cid, depth: 100},
      callback: &process_and_store/1
    )
  end

  defp process_and_store({:ok, result}) do
    result
    |> extract_insights()
    |> MyApp.Database.upsert()
  end

  defp extract_insights(result) do
    %{
      cid: result.cid,
      title: result.title,
      rating: result.rating["value"],
      review_count: result.reviews_count,
      sentiment: analyze_sentiment(result.reviews),
      last_updated: DateTime.utc_now()
    }
  end
end
```

### Pattern: Parallel Task Execution

```elixir
defmodule MyApp.ParallelFetcher do
  def fetch_all_data(business) do
    ref = make_ref()
    parent = self()

    tasks = [
      {GoogleReviews, %{cid: business.cid, depth: 50}},
      {GoogleQuestions, %{cid: business.cid, depth: 30}}
    ]

    # Start all tasks in parallel
    Enum.each(tasks, fn {module, params} ->
      DataForSEO.Supervisor.start_task(
        module,
        params,
        callback: fn result ->
          send(parent, {ref, module, result})
        end
      )
    end)

    # Collect all results
    collect_all(ref, length(tasks))
  end

  defp collect_all(ref, count, acc \\ []) do
    if count == 0 do
      {:ok, acc}
    else
      receive do
        {^ref, _module, {:ok, result}} ->
          collect_all(ref, count - 1, [result | acc])

        {^ref, _module, {:error, reason}} ->
          Logger.warn("Task failed: #{inspect(reason)}")
          collect_all(ref, count - 1, acc)
      after
        120_000 -> {:error, :timeout}
      end
    end
  end
end
```

### Pattern: Stream Processing

```elixir
defmodule MyApp.ReviewStreamer do
  def stream_reviews(business_cids) do
    Stream.resource(
      fn -> {business_cids, []} end,
      &fetch_next/1,
      &cleanup/1
    )
  end

  defp fetch_next({[], results}) do
    {:halt, {[], results}}
  end

  defp fetch_next({[cid | rest], results}) do
    case fetch_reviews_sync(cid) do
      {:ok, result} ->
        {result.reviews, {rest, [result | results]}}
      {:error, _} ->
        fetch_next({rest, results})
    end
  end

  defp fetch_reviews_sync(cid) do
    ref = make_ref()
    parent = self()

    {:ok, _} = DataForSEO.Supervisor.start_task(
      DataForSEO.Tasks.GoogleReviews,
      %{cid: cid, depth: 50},
      callback: fn result -> send(parent, {ref, result}) end
    )

    receive do
      {^ref, result} -> result
    after
      120_000 -> {:error, :timeout}
    end
  end

  defp cleanup({_cids, results}), do: results
end

# Usage:
MyApp.ReviewStreamer.stream_reviews(["cid1", "cid2", "cid3"])
|> Stream.flat_map(& &1)  # Flatten all reviews
|> Stream.filter(&(&1.rating["value"] >= 4))
|> Enum.take(100)
```

## Troubleshooting

### Common Issues

**Issue: Task times out**
```elixir
# Solution: Increase timeout
{:ok, pid} = DataForSEO.Supervisor.start_task(
  task_module,
  params,
  timeout_ms: 600_000  # 10 minutes instead of default 5
)
```

**Issue: Callback never called**
```elixir
# Check if task is still alive
tasks = DataForSEO.Supervisor.list_tasks()
IO.inspect(tasks)

# Check specific task status
{:ok, status} = DataForSEO.TaskManager.get_status(pid)
IO.inspect(status)
```

**Issue: Missing credentials**
```elixir
# Verify environment variables are set
System.get_env("DATAFORSEO_USERNAME") # Should not be nil
System.get_env("DATAFORSEO_PASSWORD") # Should not be nil
```

**Issue: Validation errors**
```elixir
# Keyword requires location
%{
  keyword: "Business Name",
  location_name: "City,State,Country"  # Required!
}

# CID and Place ID don't require location
%{cid: "12345"}  # Valid
```

## API Reference Summary

### DataForSEO.Supervisor

| Function | Description |
|----------|-------------|
| `start_task/3` | Start a new task with callback |
| `stop_task/1` | Stop a task by ID |
| `list_tasks/0` | List all active tasks with status |
| `get_stats/0` | Get system statistics |

### DataForSEO.TaskManager

| Function | Description |
|----------|-------------|
| `get_status/1` | Get task status by PID |
| `cancel/1` | Cancel task by PID |

### Task Modules

| Module | Type | Description | Max Depth |
|--------|------|-------------|-----------|
| `GoogleQuestions` | Async | Fetch Q&A from Google Business | 700 |
| `GoogleReviews` | Async | Fetch Google Maps reviews | 4490 |
| `ExtendedGoogleReviews` | Async | Multi-platform reviews | 1000 |
| `BusinessListings` | Live | Search businesses on Google Maps | 1000 |

### Schema Helper Functions

**GoogleQuestionsResult:**
- `total_question_count/1`
- `all_questions/1`
- `answered_question_count/1`
- `unanswered_question_count/1`

**GoogleQuestion:**
- `answer_count/1`
- `has_answers?/1`

**BusinessListing:**
- `generate_id/1`
- `generate_id/2`
- `with_id/1`
- `fetch_reviews/2`
- `fetch_extended_reviews/2`

## Additional Resources

- [Mix Tasks Guide](./mix_tasks.md) - CLI usage
- [DataForSEO API Documentation](https://docs.dataforseo.com/v3/) - Official API docs
- Module documentation: `mix docs` and view in browser
