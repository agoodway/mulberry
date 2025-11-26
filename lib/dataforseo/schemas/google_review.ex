defmodule DataForSEO.Schemas.GoogleReview do
  @moduledoc """
  Schema for a single Google review from DataForSEO Reviews API.

  Represents a review posted on Google Maps with full details including
  reviewer information, rating, text content, images, and owner responses.

  ## Fields

  - `:review_id` - Unique identifier for the review
  - `:review_text` - Main review content
  - `:original_review_text` - Untranslated version of the review
  - `:rating` - Rating information (map with :value, :votes_count, etc.)
  - `:timestamp` - Publication date/time in UTC
  - `:time_ago` - Relative time format (e.g., "2 months ago")
  - `:review_url` - Direct link to the review
  - `:profile_name` - Reviewer's display name
  - `:profile_url` - Link to reviewer's profile
  - `:profile_image_url` - Reviewer's avatar URL
  - `:local_guide` - Whether reviewer is a Google Local Guide
  - `:reviews_count` - Total reviews posted by this reviewer
  - `:photos_count` - Photos uploaded by this reviewer
  - `:images` - Array of images attached to the review
  - `:owner_answer` - Business owner's response text
  - `:original_owner_answer` - Untranslated owner response
  - `:owner_timestamp` - Owner response date/time
  - `:owner_time_ago` - Relative time for owner response
  - `:review_highlights` - Featured criteria mentioned
  - `:rank_group` - Ranking group number
  - `:rank_absolute` - Absolute position
  - `:position` - Position in results
  - `:xpath` - DOM location xpath
  """

  @type t :: %__MODULE__{
          review_id: String.t() | nil,
          review_text: String.t() | nil,
          original_review_text: String.t() | nil,
          rating: map() | nil,
          timestamp: String.t() | nil,
          time_ago: String.t() | nil,
          review_url: String.t() | nil,
          profile_name: String.t() | nil,
          profile_url: String.t() | nil,
          profile_image_url: String.t() | nil,
          local_guide: boolean() | nil,
          reviews_count: integer() | nil,
          photos_count: integer() | nil,
          images: [map()] | nil,
          owner_answer: String.t() | nil,
          original_owner_answer: String.t() | nil,
          owner_timestamp: String.t() | nil,
          owner_time_ago: String.t() | nil,
          review_highlights: [String.t()] | nil,
          rank_group: integer() | nil,
          rank_absolute: integer() | nil,
          position: integer() | nil,
          xpath: String.t() | nil
        }

  defstruct [
    :review_id,
    :review_text,
    :original_review_text,
    :rating,
    :timestamp,
    :time_ago,
    :review_url,
    :profile_name,
    :profile_url,
    :profile_image_url,
    :local_guide,
    :reviews_count,
    :photos_count,
    :images,
    :owner_answer,
    :original_owner_answer,
    :owner_timestamp,
    :owner_time_ago,
    :review_highlights,
    :rank_group,
    :rank_absolute,
    :position,
    :xpath
  ]

  @doc """
  Creates a GoogleReview struct from a map of attributes.

  ## Parameters

  - `attrs` - Map of review attributes from the API response

  ## Returns

  A `GoogleReview` struct with all fields populated from the attributes map.

  ## Examples

      iex> DataForSEO.Schemas.GoogleReview.new(%{
      ...>   "review_id" => "ChdDSUhNMG9nS0VJQ0FnSUQ3...",
      ...>   "review_text" => "Great place!",
      ...>   "rating" => %{"value" => 5}
      ...> })
      %DataForSEO.Schemas.GoogleReview{
        review_id: "ChdDSUhNMG9nS0VJQ0FnSUQ3...",
        review_text: "Great place!",
        rating: %{"value" => 5}
      }

  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      review_id: attrs["review_id"],
      review_text: attrs["review_text"],
      original_review_text: attrs["original_review_text"],
      rating: attrs["rating"],
      timestamp: attrs["timestamp"],
      time_ago: attrs["time_ago"],
      review_url: attrs["review_url"],
      profile_name: attrs["profile_name"],
      profile_url: attrs["profile_url"],
      profile_image_url: attrs["profile_image_url"],
      local_guide: attrs["local_guide"],
      reviews_count: attrs["reviews_count"],
      photos_count: attrs["photos_count"],
      images: attrs["images"],
      owner_answer: attrs["owner_answer"],
      original_owner_answer: attrs["original_owner_answer"],
      owner_timestamp: attrs["owner_timestamp"],
      owner_time_ago: attrs["owner_time_ago"],
      review_highlights: attrs["review_highlights"],
      rank_group: attrs["rank_group"],
      rank_absolute: attrs["rank_absolute"],
      position: attrs["position"],
      xpath: attrs["xpath"]
    }
  end
end
