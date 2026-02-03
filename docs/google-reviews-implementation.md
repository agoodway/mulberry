# Google Reviews Implementation Guide

This guide covers how to use Mulberry's Google Reviews functionality programmatically in your Elixir applications.

## Overview

Mulberry provides two task modules for fetching Google reviews:

- **`DataForSEO.Tasks.GoogleReviews`** - Fetches Google Maps reviews only
- **`DataForSEO.Tasks.ExtendedGoogleReviews`** - Fetches reviews from Google Maps AND other platforms (TripAdvisor, Yelp, Trustpilot, etc.)

Both tasks use DataForSEO's async API and return structured data via callbacks.

## Prerequisites

Ensure the DataForSEO supervisor is started in your application:

```elixir
# In your application.ex
children = [
  DataForSEO.Supervisor
]
```

## Basic Usage

### Fetching Reviews by CID

The CID (Customer ID) is the most stable identifier and is returned by the business listings API:

```elixir
{:ok, pid} = DataForSEO.Supervisor.start_task(
  DataForSEO.Tasks.GoogleReviews,
  %{
    cid: "10179360708466590899",
    depth: 100,
    sort_by: "newest"
  },
  callback: fn {:ok, result} ->
    IO.puts("Business: #{result.title}")
    IO.puts("Rating: #{result.rating["value"]}/5")
    IO.puts("Reviews fetched: #{length(result.reviews)}")
  end
)
```

### Fetching Reviews by Business Name

When using a keyword search, you must provide a location:

```elixir
{:ok, pid} = DataForSEO.Supervisor.start_task(
  DataForSEO.Tasks.GoogleReviews,
  %{
    keyword: "Joe's Pizza",
    location_name: "New York",
    depth: 50,
    language_code: "en"
  },
  callback: fn {:ok, result} ->
    Enum.each(result.reviews, fn review ->
      IO.puts("#{review.profile_name}: #{review.review_text}")
    end)
  end
)
```

### Fetching Reviews by Place ID

```elixir
{:ok, pid} = DataForSEO.Supervisor.start_task(
  DataForSEO.Tasks.GoogleReviews,
  %{
    place_id: "ChIJOwg_06VPwokRYv534QaPC8g",
    depth: 200,
    sort_by: "highest_rating"
  },
  callback: fn {:ok, result} ->
    # Process results
  end
)
```

## Extended Reviews (Multi-Platform)

Extended reviews fetch from multiple platforms but cost more:

```elixir
{:ok, pid} = DataForSEO.Supervisor.start_task(
  DataForSEO.Tasks.ExtendedGoogleReviews,
  %{
    cid: "10179360708466590899",
    depth: 100,
    sort_by: "newest"
  },
  callback: fn {:ok, result} ->
    # Reviews now include sources beyond Google Maps
    Enum.each(result.reviews, fn review ->
      IO.inspect(review)
    end)
  end
)
```

## Parameters Reference

### Business Identifier (choose one)

| Parameter | Description | Notes |
|-----------|-------------|-------|
| `:keyword` | Business name (max 700 chars) | Requires location parameter |
| `:cid` | Google Customer ID | Recommended - most stable identifier |
| `:place_id` | Google Place ID | Alternative to CID |

### Location (required for keyword searches)

| Parameter | Description | Example |
|-----------|-------------|---------|
| `:location_name` | Full location name | `"New York"` |
| `:location_code` | Numeric location code | `2840` (United States) |
| `:location_coordinate` | Lat/lng coordinates | `"40.7128,-74.0060"` |

### Optional Parameters

| Parameter | Description | Default | Valid Values |
|-----------|-------------|---------|--------------|
| `:depth` | Number of reviews to fetch | 10 (regular) / 20 (extended) | 1-4490 (regular) / 1-1000 (extended) |
| `:sort_by` | Sort order | `"relevant"` | `"newest"`, `"highest_rating"`, `"lowest_rating"`, `"relevant"` |
| `:language_code` | Language code | `"en"` | Any ISO language code |
| `:priority` | Task priority | `1` | `1` (normal) or `2` (high priority, additional cost) |
| `:tag` | User identifier | - | Max 255 chars |

## API Response Structure

The DataForSEO API returns JSON responses that are parsed into Elixir structs. Understanding the raw API structure helps when debugging or working directly with responses.

### Raw API Response Format

```json
{
  "tasks": [
    {
      "id": "task_id_123",
      "status_code": 20000,
      "status_message": "Ok.",
      "result": [
        {
          "keyword": "Joe's Pizza",
          "place_id": "ChIJOwg_06VPwokRYv534QaPC8g",
          "cid": "10179360708466590899",
          "title": "Joe's Pizza",
          "sub_title": "123 Main Street, New York, NY",
          "rating": {
            "value": 4.5,
            "votes_count": 150,
            "rating_max": 5
          },
          "reviews_count": 150,
          "items_count": 100,
          "items": [
            {
              "review_id": "ChdDSUhNMG9nS0VJQ0FnSUQ3...",
              "review_text": "Great pizza and friendly staff!",
              "rating": {"value": 5},
              "timestamp": "2024-01-10T14:30:00Z",
              "time_ago": "2 weeks ago",
              "profile_name": "John Doe",
              "profile_url": "https://www.google.com/maps/contrib/...",
              "profile_image_url": "https://lh3.googleusercontent.com/...",
              "local_guide": true,
              "reviews_count": 45,
              "photos_count": 12,
              "images": [
                {"url": "https://...", "description": "Pizza photo"}
              ],
              "owner_answer": "Thanks for your kind words!",
              "owner_timestamp": "2024-01-11T10:00:00Z",
              "owner_time_ago": "1 week ago",
              "review_highlights": ["Food", "Service"]
            }
          ],
          "check_url": "https://www.google.com/maps/place/...",
          "datetime": "2024-01-15T12:00:00Z",
          "location_code": 2840,
          "language_code": "en",
          "se_domain": "google.com",
          "feature_id": "0x89c25fe2..."
        }
      ]
    }
  ]
}
```

## Working with Results

The callback receives a `DataForSEO.Schemas.GoogleReviewsResult` struct parsed from the API response:

### GoogleReviewsResult Struct

```elixir
%DataForSEO.Schemas.GoogleReviewsResult{
  keyword: "Joe's Pizza",           # Business name searched (string)
  place_id: "ChIJOwg_...",          # Google Place ID (string)
  cid: "10179360708466590899",      # Google Customer ID (string)
  title: "Joe's Pizza",             # Business title (string)
  sub_title: "123 Main St, NY",     # Business address (string)
  rating: %{                         # Overall rating (map)
    "value" => 4.5,                 # Average rating (float)
    "votes_count" => 150,           # Total number of ratings (integer)
    "rating_max" => 5               # Maximum rating value (integer)
  },
  reviews_count: 150,               # Total reviews available (integer)
  items_count: 100,                 # Reviews in this result (integer)
  reviews: [%GoogleReview{...}],    # List of review structs (list)
  check_url: "https://...",         # Direct link to reviews (string)
  datetime: "2024-01-15T...",       # Retrieval timestamp (string, ISO 8601)
  location_code: 2840,              # Location code used (integer)
  language_code: "en",              # Language code used (string)
  se_domain: "google.com",          # Google domain (string)
  feature_id: "..."                 # Internal Google feature ID (string)
}
```

### GoogleReview Struct

Each review in the `reviews` list is a `DataForSEO.Schemas.GoogleReview` struct:

```elixir
%DataForSEO.Schemas.GoogleReview{
  review_id: "ChdDSUhNMG9nS0VJQ0FnSUQ3...",  # Unique review ID (string)
  review_text: "Great pizza!",                 # Review content (string)
  original_review_text: nil,                   # Untranslated text (string | nil)
  rating: %{"value" => 5},                     # Rating map with "value" key (1-5)
  timestamp: "2024-01-10T14:30:00Z",          # Publication time (string, ISO 8601)
  time_ago: "2 weeks ago",                     # Relative time (string)
  review_url: "https://...",                   # Direct link (string)
  profile_name: "John Doe",                    # Reviewer name (string)
  profile_url: "https://...",                  # Reviewer profile (string)
  profile_image_url: "https://...",            # Avatar URL (string)
  local_guide: true,                           # Local Guide status (boolean)
  reviews_count: 45,                           # Reviewer's total reviews (integer)
  photos_count: 12,                            # Reviewer's photos (integer)
  images: [%{url: "...", description: "..."}], # Attached images (list of maps)
  owner_answer: "Thanks!",                     # Owner response (string | nil)
  original_owner_answer: nil,                  # Untranslated response (string | nil)
  owner_timestamp: "2024-01-11T...",          # Response time (string | nil)
  owner_time_ago: "1 week ago",                # Relative response time (string | nil)
  review_highlights: ["Food", "Service"],      # Featured aspects (list of strings)
  rank_group: 1,                               # Position in group (integer)
  rank_absolute: 1,                            # Absolute position (integer)
  position: 1,                                 # Display position (integer)
  xpath: "/html/body/..."                      # DOM location (string)
}
```

### Field Types Reference

| Field | Type | Nullable | Description |
|-------|------|----------|-------------|
| `review_id` | `String.t()` | Yes | Unique identifier for the review |
| `review_text` | `String.t()` | Yes | Main review content |
| `original_review_text` | `String.t()` | Yes | Untranslated version if translated |
| `rating` | `map()` | Yes | Contains `"value"` (1-5) and optionally `"votes_count"` |
| `timestamp` | `String.t()` | Yes | ISO 8601 datetime string |
| `time_ago` | `String.t()` | Yes | Human-readable relative time |
| `review_url` | `String.t()` | Yes | Direct URL to the review |
| `profile_name` | `String.t()` | Yes | Display name of reviewer |
| `profile_url` | `String.t()` | Yes | Link to reviewer's Google profile |
| `profile_image_url` | `String.t()` | Yes | Avatar image URL |
| `local_guide` | `boolean()` | Yes | Whether reviewer is a Local Guide |
| `reviews_count` | `integer()` | Yes | Total reviews by this user |
| `photos_count` | `integer()` | Yes | Total photos by this user |
| `images` | `[map()]` | Yes | List of image maps with `url` and `description` |
| `owner_answer` | `String.t()` | Yes | Business owner's response |
| `original_owner_answer` | `String.t()` | Yes | Untranslated owner response |
| `owner_timestamp` | `String.t()` | Yes | When owner responded |
| `owner_time_ago` | `String.t()` | Yes | Relative time for owner response |
| `review_highlights` | `[String.t()]` | Yes | Featured criteria mentioned |
| `rank_group` | `integer()` | Yes | Position within rating group |
| `rank_absolute` | `integer()` | Yes | Absolute position in results |
| `position` | `integer()` | Yes | Display position |
| `xpath` | `String.t()` | Yes | XPath location in DOM |

## Common Patterns

### Filtering Reviews

```elixir
callback = fn {:ok, result} ->
  # Filter 5-star reviews only
  five_star = Enum.filter(result.reviews, fn r ->
    get_in(r.rating, ["value"]) == 5
  end)

  # Filter reviews with owner responses
  with_response = Enum.filter(result.reviews, & &1.owner_answer)

  # Filter recent reviews (last 30 days)
  recent = Enum.filter(result.reviews, fn r ->
    case DateTime.from_iso8601(r.timestamp) do
      {:ok, datetime, _} ->
        DateTime.diff(DateTime.utc_now(), datetime, :day) <= 30
      _ -> false
    end
  end)
end
```

### Aggregating Review Data

```elixir
callback = fn {:ok, result} ->
  # Calculate average rating from fetched reviews
  avg_rating =
    result.reviews
    |> Enum.map(&get_in(&1.rating, ["value"]) || 0)
    |> then(fn ratings -> Enum.sum(ratings) / length(ratings) end)

  # Count reviews by rating
  by_rating = Enum.group_by(result.reviews, &get_in(&1.rating, ["value"]))

  # Find most common words in reviews
  words =
    result.reviews
    |> Enum.flat_map(fn r ->
      (r.review_text || "")
      |> String.downcase()
      |> String.split(~r/\W+/, trim: true)
    end)
    |> Enum.frequencies()
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.take(10)
end
```

### Handling Errors

```elixir
callback = fn
  {:ok, result} ->
    IO.puts("Successfully fetched #{length(result.reviews)} reviews")

  {:error, {:task_creation_failed, message}} ->
    IO.puts("Task creation failed: #{message}")

  {:error, {:task_failed, message}} ->
    IO.puts("Task execution failed: #{message}")

  {:error, {:invalid_params, message}} ->
    IO.puts("Invalid parameters: #{message}")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
```

### Saving to Database

```elixir
callback = fn {:ok, result} ->
  # Save business info
  business = %Business{
    cid: result.cid,
    place_id: result.place_id,
    name: result.title,
    address: result.sub_title,
    rating: get_in(result.rating, ["value"]),
    total_reviews: result.reviews_count
  }
  |> Repo.insert!(on_conflict: :replace_all, conflict_target: :cid)

  # Save reviews
  Enum.each(result.reviews, fn review ->
    %Review{
      business_id: business.id,
      review_id: review.review_id,
      text: review.review_text,
      rating: get_in(review.rating, ["value"]),
      author: review.profile_name,
      timestamp: review.timestamp,
      owner_response: review.owner_answer
    }
    |> Repo.insert!(on_conflict: :nothing, conflict_target: :review_id)
  end)
end
```

## Integration with Business Listings

A common workflow is to fetch business listings first, then get reviews:

```elixir
# Step 1: Find businesses
{:ok, pid} = DataForSEO.Supervisor.start_task(
  DataForSEO.Tasks.BusinessListings,
  %{
    categories: ["pizza_restaurant"],
    location_coordinate: "40.7128,-74.0060,5",
    limit: 10
  },
  callback: fn {:ok, listings} ->
    # Step 2: Fetch reviews for each business
    Enum.each(listings.items, fn business ->
      {:ok, _} = DataForSEO.Supervisor.start_task(
        DataForSEO.Tasks.GoogleReviews,
        %{
          cid: business.cid,
          depth: 50
        },
        callback: fn {:ok, reviews_result} ->
          # Process reviews for this business
          IO.puts("#{business.title}: #{length(reviews_result.reviews)} reviews")
        end
      )
    end)
  end
)
```

## Pricing Considerations

### Regular Reviews
- Billed per 10 reviews
- CID/place_id: Standard pricing
- Keyword: Slightly higher (requires location resolution)

### Extended Reviews
- Billed per 20 reviews
- CID/place_id: 2x standard pricing
- Keyword: 3x standard pricing

## Best Practices

1. **Use CID when possible** - It's the most stable identifier and doesn't require location parameters
2. **Start with small depth** - Test with 10-20 reviews before fetching larger amounts
3. **Handle rate limits** - DataForSEO has rate limits; implement backoff if needed
4. **Store review_id** - Use `review_id` for deduplication when storing reviews
5. **Check owner_answer** - Owner responses often contain valuable business insights
6. **Monitor costs** - Extended reviews are significantly more expensive

## Troubleshooting

### No Reviews Found
- Verify the CID/place_id is correct
- Check that the business has public reviews
- Some businesses disable review display

### Task Timeout
- Large depth values take longer to fetch
- Consider fetching in smaller batches
- Use priority: 2 for faster processing (additional cost)

### Invalid Parameters
- Keyword searches require a location parameter
- CID and place_id searches don't need location (defaults to US)
- Depth must be within valid ranges
