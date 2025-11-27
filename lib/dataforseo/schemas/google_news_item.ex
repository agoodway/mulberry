defmodule DataForSEO.Schemas.GoogleNewsItem do
  @moduledoc """
  Schema for a single Google News article from DataForSEO News API.

  Represents a news article from Google News search results with details including
  title, source, publication time, and content snippet.

  ## Fields

  - `:title` - Article headline/title
  - `:url` - Direct link to the article
  - `:domain` - Source domain (e.g., "nytimes.com")
  - `:source` - News source name (e.g., "The New York Times")
  - `:snippet` - Article preview text/description
  - `:image_url` - Article thumbnail/image URL
  - `:time_published` - Relative time (e.g., "2 hours ago")
  - `:timestamp` - Publication date/time in UTC
  - `:rank_group` - Ranking group number
  - `:rank_absolute` - Absolute position across all SERP elements
  - `:position` - Position within results
  - `:xpath` - DOM location xpath
  - `:type` - Item type (e.g., "news_search")
  """

  @type t :: %__MODULE__{
          title: String.t() | nil,
          url: String.t() | nil,
          domain: String.t() | nil,
          source: String.t() | nil,
          snippet: String.t() | nil,
          image_url: String.t() | nil,
          time_published: String.t() | nil,
          timestamp: String.t() | nil,
          rank_group: integer() | nil,
          rank_absolute: integer() | nil,
          position: integer() | nil,
          xpath: String.t() | nil,
          type: String.t() | nil
        }

  defstruct [
    :title,
    :url,
    :domain,
    :source,
    :snippet,
    :image_url,
    :time_published,
    :timestamp,
    :rank_group,
    :rank_absolute,
    :position,
    :xpath,
    :type
  ]

  @doc """
  Creates a GoogleNewsItem struct from a map of attributes.

  ## Parameters

  - `attrs` - Map of news item attributes from the API response

  ## Returns

  A `GoogleNewsItem` struct with all fields populated from the attributes map.

  ## Examples

      iex> DataForSEO.Schemas.GoogleNewsItem.new(%{
      ...>   "title" => "Breaking News Story",
      ...>   "source" => "CNN",
      ...>   "domain" => "cnn.com",
      ...>   "url" => "https://cnn.com/article",
      ...>   "time_published" => "2 hours ago"
      ...> })
      %DataForSEO.Schemas.GoogleNewsItem{
        title: "Breaking News Story",
        source: "CNN",
        domain: "cnn.com",
        url: "https://cnn.com/article",
        time_published: "2 hours ago"
      }

  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      title: attrs["title"],
      url: attrs["url"],
      domain: attrs["domain"],
      source: attrs["source"],
      snippet: attrs["snippet"],
      image_url: attrs["image_url"],
      time_published: attrs["time_published"],
      timestamp: attrs["timestamp"],
      rank_group: attrs["rank_group"],
      rank_absolute: attrs["rank_absolute"],
      position: attrs["position"],
      xpath: attrs["xpath"],
      type: attrs["type"]
    }
  end
end
