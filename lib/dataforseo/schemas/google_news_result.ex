defmodule DataForSEO.Schemas.GoogleNewsResult do
  @moduledoc """
  Schema for Google News search results from DataForSEO News API.

  Contains a collection of news articles along with metadata about the search
  query and parameters used.

  ## Fields

  - `:keyword` - News search keyword/query
  - `:location_code` - Location code used for search
  - `:language_code` - Language code used for search
  - `:se_domain` - Google domain used (e.g., "google.com")
  - `:check_url` - Direct link to Google News search page
  - `:datetime` - Retrieval timestamp
  - `:se_results_count` - Total results in SERP
  - `:items_count` - Number of news items in this result
  - `:news_items` - List of `DataForSEO.Schemas.GoogleNewsItem` structs
  - `:type` - Result type (always "news")

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleNewsResult{
      ...>   keyword: "artificial intelligence",
      ...>   items_count: 50,
      ...>   news_items: [%DataForSEO.Schemas.GoogleNewsItem{title: "AI Breakthrough"}]
      ...> }
      %DataForSEO.Schemas.GoogleNewsResult{keyword: "artificial intelligence", items_count: 50, ...}

  """

  alias DataForSEO.Schemas.GoogleNewsItem

  @type t :: %__MODULE__{
          keyword: String.t() | nil,
          location_code: integer() | nil,
          language_code: String.t() | nil,
          se_domain: String.t() | nil,
          check_url: String.t() | nil,
          datetime: String.t() | nil,
          se_results_count: integer() | nil,
          items_count: integer() | nil,
          news_items: [GoogleNewsItem.t()],
          type: String.t() | nil
        }

  defstruct [
    :keyword,
    :location_code,
    :language_code,
    :se_domain,
    :check_url,
    :datetime,
    :se_results_count,
    :items_count,
    :type,
    news_items: []
  ]

  @doc """
  Creates a GoogleNewsResult struct from a map of attributes.

  Parses the result data from the DataForSEO API response and converts
  each news item into a `GoogleNewsItem` struct.

  ## Parameters

  - `attrs` - Map containing the result data from the API response

  ## Returns

  A `GoogleNewsResult` struct with parsed news items.

  ## Examples

      iex> DataForSEO.Schemas.GoogleNewsResult.new(%{
      ...>   "keyword" => "technology news",
      ...>   "items_count" => 50,
      ...>   "items" => [
      ...>     %{"title" => "Tech Innovation", "source" => "TechCrunch"}
      ...>   ]
      ...> })
      %DataForSEO.Schemas.GoogleNewsResult{
        keyword: "technology news",
        items_count: 50,
        news_items: [%DataForSEO.Schemas.GoogleNewsItem{title: "Tech Innovation", ...}]
      }

  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    news_items =
      attrs
      |> Map.get("items", [])
      |> Enum.filter(fn item -> item["type"] == "news_search" end)
      |> Enum.map(&GoogleNewsItem.new/1)

    %__MODULE__{
      keyword: attrs["keyword"],
      location_code: attrs["location_code"],
      language_code: attrs["language_code"],
      se_domain: attrs["se_domain"],
      check_url: attrs["check_url"],
      datetime: attrs["datetime"],
      se_results_count: attrs["se_results_count"],
      items_count: attrs["items_count"],
      type: attrs["type"],
      news_items: news_items
    }
  end

  @doc """
  Returns the number of news items in the result.

  ## Parameters

  - `result` - A `GoogleNewsResult` struct

  ## Returns

  The count of news items in the result.

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleNewsResult{news_items: [%{}, %{}, %{}]}
      iex> DataForSEO.Schemas.GoogleNewsResult.news_count(result)
      3

  """
  @spec news_count(t()) :: non_neg_integer()
  def news_count(%__MODULE__{news_items: news_items}), do: length(news_items)

  @doc """
  Filters news items by domain.

  ## Parameters

  - `result` - A `GoogleNewsResult` struct
  - `domain` - The domain to filter by (e.g., "nytimes.com")

  ## Returns

  A list of `GoogleNewsItem` structs matching the domain.

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleNewsResult{
      ...>   news_items: [
      ...>     %DataForSEO.Schemas.GoogleNewsItem{domain: "nytimes.com"},
      ...>     %DataForSEO.Schemas.GoogleNewsItem{domain: "cnn.com"}
      ...>   ]
      ...> }
      iex> DataForSEO.Schemas.GoogleNewsResult.filter_by_domain(result, "nytimes.com")
      [%DataForSEO.Schemas.GoogleNewsItem{domain: "nytimes.com"}]

  """
  @spec filter_by_domain(t(), String.t()) :: [GoogleNewsItem.t()]
  def filter_by_domain(%__MODULE__{news_items: news_items}, domain) do
    Enum.filter(news_items, fn item ->
      item.domain == domain
    end)
  end

  @doc """
  Gets news items published within the last N hours.

  ## Parameters

  - `result` - A `GoogleNewsResult` struct
  - `hours` - Number of hours to look back (default: 24)

  ## Returns

  A list of `GoogleNewsItem` structs published within the timeframe.

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleNewsResult{
      ...>   news_items: [
      ...>     %DataForSEO.Schemas.GoogleNewsItem{time_published: "2 hours ago"},
      ...>     %DataForSEO.Schemas.GoogleNewsItem{time_published: "3 days ago"}
      ...>   ]
      ...> }
      iex> recent = DataForSEO.Schemas.GoogleNewsResult.recent_news(result, 24)
      iex> length(recent)
      1

  """
  @spec recent_news(t(), non_neg_integer()) :: [GoogleNewsItem.t()]
  def recent_news(%__MODULE__{news_items: news_items}, hours \\ 24) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours * 3600, :second)
    Enum.filter(news_items, &recent_news?(&1, cutoff, hours))
  end

  @doc """
  Groups news items by source/domain.

  ## Parameters

  - `result` - A `GoogleNewsResult` struct

  ## Returns

  A map where keys are source names and values are lists of news items from that source.

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleNewsResult{
      ...>   news_items: [
      ...>     %DataForSEO.Schemas.GoogleNewsItem{source: "CNN"},
      ...>     %DataForSEO.Schemas.GoogleNewsItem{source: "CNN"}
      ...>   ]
      ...> }
      iex> DataForSEO.Schemas.GoogleNewsResult.group_by_source(result)
      %{"CNN" => [%DataForSEO.Schemas.GoogleNewsItem{...}, %DataForSEO.Schemas.GoogleNewsItem{...}]}

  """
  @spec group_by_source(t()) :: %{String.t() => [GoogleNewsItem.t()]}
  def group_by_source(%__MODULE__{news_items: news_items}) do
    Enum.group_by(news_items, fn item -> item.source || item.domain end)
  end

  # Private helpers

  defp recent_news?(item, cutoff, hours) do
    case item.timestamp do
      nil -> parse_relative_time(item.time_published, hours)
      timestamp_str -> timestamp_recent?(timestamp_str, cutoff)
    end
  end

  defp timestamp_recent?(timestamp_str, cutoff) do
    case DateTime.from_iso8601(timestamp_str) do
      {:ok, dt, _} -> DateTime.compare(dt, cutoff) == :gt
      _ -> false
    end
  end

  defp parse_relative_time(nil, _hours), do: false

  defp parse_relative_time(time_str, hours) when is_binary(time_str) do
    cond do
      within_minutes?(time_str) -> true
      within_hours?(time_str, hours) -> true
      within_days?(time_str, hours) -> true
      true -> false
    end
  end

  defp within_minutes?(time_str) do
    String.contains?(time_str, "minute") or String.contains?(time_str, "min")
  end

  defp within_hours?(time_str, hours) do
    if String.contains?(time_str, "hour") do
      extract_hours(time_str, hours)
    else
      false
    end
  end

  defp within_days?(time_str, hours) do
    if String.contains?(time_str, "day") do
      extract_days(time_str, hours)
    else
      false
    end
  end

  defp extract_hours(time_str, max_hours) do
    case Regex.run(~r/(\d+)\s*hour/, time_str) do
      [_, num_str] -> parse_and_compare(num_str, max_hours, 1)
      _ -> true
    end
  end

  defp extract_days(time_str, max_hours) do
    case Regex.run(~r/(\d+)\s*day/, time_str) do
      [_, num_str] -> parse_and_compare(num_str, max_hours, 24)
      _ -> false
    end
  end

  defp parse_and_compare(num_str, max_hours, multiplier) do
    case Integer.parse(num_str) do
      {num, _} -> num * multiplier <= max_hours
      _ -> false
    end
  end
end
