defmodule DataForSEO.Schemas.BusinessListing do
  @moduledoc """
  Schema for a single business listing from DataForSEO Business Listings API.

  Represents a business entity listed on Google Maps with detailed information
  including contact details, ratings, operational hours, and geographic data.

  ## Fields

  - `:type` - Type of the item (typically "business_listing")
  - `:title` - Business name
  - `:description` - Business description
  - `:category` - Primary business category (human-readable)
  - `:category_ids` - List of category identifiers
  - `:address` - Full formatted address
  - `:address_info` - Structured address components (map)
  - `:phone` - Business phone number
  - `:url` - Google Maps URL for this business
  - `:domain` - Business website domain
  - `:latitude` - Geographic latitude
  - `:longitude` - Geographic longitude
  - `:place_id` - Google Place ID
  - `:cid` - Google CID (Customer ID)
  - `:is_claimed` - Whether business is verified on Google Maps
  - `:rating` - Rating information (map with :value and :votes_count)
  - `:rating_distribution` - Distribution of ratings (map)
  - `:work_time` - Business hours (map)
  - `:popular_times` - Popular visit times (map)
  - `:logo` - Business logo URL
  - `:main_image` - Main business image URL
  - `:total_photos` - Total number of photos
  - `:attributes` - Additional business attributes (map)
  - `:last_updated_time` - Last update timestamp
  - `:first_seen` - First seen timestamp
  """

  @type t :: %__MODULE__{
          type: String.t() | nil,
          title: String.t() | nil,
          description: String.t() | nil,
          category: String.t() | nil,
          category_ids: [String.t()] | nil,
          address: String.t() | nil,
          address_info: map() | nil,
          phone: String.t() | nil,
          url: String.t() | nil,
          domain: String.t() | nil,
          latitude: float() | nil,
          longitude: float() | nil,
          place_id: String.t() | nil,
          cid: String.t() | nil,
          is_claimed: boolean() | nil,
          rating: map() | nil,
          rating_distribution: map() | nil,
          work_time: map() | nil,
          popular_times: map() | nil,
          logo: String.t() | nil,
          main_image: String.t() | nil,
          total_photos: integer() | nil,
          attributes: map() | nil,
          last_updated_time: String.t() | nil,
          first_seen: String.t() | nil
        }

  defstruct [
    :type,
    :title,
    :description,
    :category,
    :category_ids,
    :address,
    :address_info,
    :phone,
    :url,
    :domain,
    :latitude,
    :longitude,
    :place_id,
    :cid,
    :is_claimed,
    :rating,
    :rating_distribution,
    :work_time,
    :popular_times,
    :logo,
    :main_image,
    :total_photos,
    :attributes,
    :last_updated_time,
    :first_seen
  ]

  @doc """
  Creates a BusinessListing struct from a map of attributes.

  ## Parameters

  - `attrs` - Map of business listing attributes from the API response

  ## Returns

  A `BusinessListing` struct with all fields populated from the attributes map.

  ## Examples

      iex> DataForSEO.Schemas.BusinessListing.new(%{
      ...>   "title" => "Joe's Pizza",
      ...>   "category" => "Pizza restaurant",
      ...>   "rating" => %{"value" => 4.5, "votes_count" => 150}
      ...> })
      %DataForSEO.Schemas.BusinessListing{
        title: "Joe's Pizza",
        category: "Pizza restaurant",
        rating: %{"value" => 4.5, "votes_count" => 150}
      }

  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      type: attrs["type"],
      title: attrs["title"],
      description: attrs["description"],
      category: attrs["category"],
      category_ids: attrs["category_ids"],
      address: attrs["address"],
      address_info: attrs["address_info"],
      phone: attrs["phone"],
      url: attrs["url"],
      domain: attrs["domain"],
      latitude: attrs["latitude"],
      longitude: attrs["longitude"],
      place_id: attrs["place_id"],
      cid: attrs["cid"],
      is_claimed: attrs["is_claimed"],
      rating: attrs["rating"],
      rating_distribution: attrs["rating_distribution"],
      work_time: attrs["work_time"],
      popular_times: attrs["popular_times"],
      logo: attrs["logo"],
      main_image: attrs["main_image"],
      total_photos: attrs["total_photos"],
      attributes: attrs["attributes"],
      last_updated_time: attrs["last_updated_time"],
      first_seen: attrs["first_seen"]
    }
  end
end
