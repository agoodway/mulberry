defmodule DataForSEO.Schemas.GoogleReviewsResult do
  @moduledoc """
  Schema for Google reviews search results from DataForSEO Reviews API.

  Contains a collection of reviews along with metadata about the business
  and overall ratings.

  ## Fields

  - `:keyword` - Business name searched
  - `:place_id` - Google Place ID
  - `:cid` - Google Customer ID
  - `:title` - Business name
  - `:sub_title` - Business address/location
  - `:rating` - Overall rating information (map)
  - `:reviews_count` - Total number of reviews
  - `:items_count` - Number of reviews in this result
  - `:reviews` - List of `DataForSEO.Schemas.GoogleReview` structs
  - `:check_url` - Direct link to Google reviews page
  - `:datetime` - Retrieval timestamp
  - `:location_code` - Location code used
  - `:language_code` - Language code used
  - `:se_domain` - Google domain used (e.g., "google.com")
  - `:feature_id` - Google feature identifier

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleReviewsResult{
      ...>   keyword: "Joe's Pizza",
      ...>   reviews_count: 150,
      ...>   reviews: [%DataForSEO.Schemas.GoogleReview{review_text: "Great pizza!"}]
      ...> }
      %DataForSEO.Schemas.GoogleReviewsResult{keyword: "Joe's Pizza", reviews_count: 150, ...}

  """

  alias DataForSEO.Schemas.GoogleReview

  @type t :: %__MODULE__{
          keyword: String.t() | nil,
          place_id: String.t() | nil,
          cid: String.t() | nil,
          title: String.t() | nil,
          sub_title: String.t() | nil,
          rating: map() | nil,
          reviews_count: integer() | nil,
          items_count: integer() | nil,
          reviews: [GoogleReview.t()],
          check_url: String.t() | nil,
          datetime: String.t() | nil,
          location_code: integer() | nil,
          language_code: String.t() | nil,
          se_domain: String.t() | nil,
          feature_id: String.t() | nil
        }

  defstruct [
    :keyword,
    :place_id,
    :cid,
    :title,
    :sub_title,
    :rating,
    :reviews_count,
    :items_count,
    :check_url,
    :datetime,
    :location_code,
    :language_code,
    :se_domain,
    :feature_id,
    reviews: []
  ]

  @doc """
  Creates a GoogleReviewsResult struct from a map of attributes.

  Parses the result data from the DataForSEO API response and converts
  each review item into a `GoogleReview` struct.

  ## Parameters

  - `attrs` - Map containing the result data from the API response

  ## Returns

  A `GoogleReviewsResult` struct with parsed reviews.

  ## Examples

      iex> DataForSEO.Schemas.GoogleReviewsResult.new(%{
      ...>   "keyword" => "Joe's Pizza",
      ...>   "reviews_count" => 150,
      ...>   "items" => [
      ...>     %{"review_text" => "Great pizza!", "rating" => %{"value" => 5}}
      ...>   ]
      ...> })
      %DataForSEO.Schemas.GoogleReviewsResult{
        keyword: "Joe's Pizza",
        reviews_count: 150,
        reviews: [%DataForSEO.Schemas.GoogleReview{review_text: "Great pizza!", ...}]
      }

  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    # Use || to handle explicit nil values from API (Map.get default only works for missing keys)
    reviews =
      (attrs["items"] || [])
      |> Enum.map(&GoogleReview.new/1)

    %__MODULE__{
      keyword: attrs["keyword"],
      place_id: attrs["place_id"],
      cid: attrs["cid"],
      title: attrs["title"],
      sub_title: attrs["sub_title"],
      rating: attrs["rating"],
      reviews_count: attrs["reviews_count"],
      items_count: attrs["items_count"],
      reviews: reviews,
      check_url: attrs["check_url"],
      datetime: attrs["datetime"],
      location_code: attrs["location_code"],
      language_code: attrs["language_code"],
      se_domain: attrs["se_domain"],
      feature_id: attrs["feature_id"]
    }
  end
end
