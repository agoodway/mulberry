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
          unique_id: String.t() | nil,
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
    :unique_id,
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

  @doc """
  Generates a unique identifier for the business listing.

  Uses the configured strategy from application config or per-request options.
  Returns `nil` if the required field is missing.

  ## Strategies

  - `:cid` - Uses Google CID directly (default, most stable)
  - `:place_id` - Uses Google Place ID directly
  - `:composite_hash` - SHA256 hash of configured fields
  - `:custom` - User-provided hash function

  ## Options

  - `:strategy` - ID generation strategy (default from config or `:cid`)
  - `:composite_fields` - Fields to include in composite hash (default: `[:cid, :place_id]`)
  - `:prefix` - Optional prefix for the ID (default: none)
  - `:hash_fn` - Custom function for `:custom` strategy

  ## Examples

      # Use default CID strategy
      iex> listing = %BusinessListing{cid: "12345"}
      iex> BusinessListing.generate_id(listing)
      "12345"

      # Use Place ID strategy
      iex> listing = %BusinessListing{place_id: "ChIJ..."}
      iex> BusinessListing.generate_id(listing, strategy: :place_id)
      "ChIJ..."

      # Composite hash with prefix
      iex> listing = %BusinessListing{cid: "12345", place_id: "ChIJ..."}
      iex> BusinessListing.generate_id(listing, strategy: :composite_hash, prefix: "bl_")
      "bl_a3f5c8d9e2b1f4a7..."

      # Returns nil when field missing
      iex> listing = %BusinessListing{cid: nil}
      iex> BusinessListing.generate_id(listing)
      nil

  """
  @spec generate_id(t(), keyword()) :: String.t() | nil
  def generate_id(listing, opts \\ []) do
    strategy = opts[:strategy] || get_config(:id_strategy, :cid)

    prefix =
      if Keyword.has_key?(opts, :prefix) do
        opts[:prefix]
      else
        get_config(:id_prefix, nil)
      end

    id = generate_id_by_strategy(listing, strategy, opts)

    apply_prefix(id, prefix)
  end

  @doc """
  Same as `generate_id/2` but raises an error if ID cannot be generated.

  ## Examples

      iex> listing = %BusinessListing{cid: "12345"}
      iex> BusinessListing.generate_id!(listing)
      "12345"

      iex> listing = %BusinessListing{cid: nil}
      iex> BusinessListing.generate_id!(listing)
      ** (RuntimeError) Cannot generate ID: required field is missing

  """
  @spec generate_id!(t(), keyword()) :: String.t()
  def generate_id!(listing, opts \\ []) do
    case generate_id(listing, opts) do
      nil ->
        raise "Cannot generate ID: required field is missing"

      id ->
        id
    end
  end

  @doc """
  Returns a listing with the unique_id field populated.

  ## Examples

      iex> listing = %BusinessListing{cid: "12345"}
      iex> BusinessListing.with_id(listing)
      %BusinessListing{cid: "12345", unique_id: "12345"}

  """
  @spec with_id(t(), keyword()) :: t()
  def with_id(listing, opts \\ []) do
    unique_id = generate_id(listing, opts)
    %{listing | unique_id: unique_id}
  end

  # Private functions

  defp get_config(key, default) do
    case Application.get_env(:mulberry, __MODULE__, []) do
      config when is_list(config) ->
        Keyword.get(config, key, default)

      _ ->
        default
    end
  end

  defp generate_id_by_strategy(listing, strategy, opts) do
    case strategy do
      :cid ->
        normalize_id(listing.cid)

      :place_id ->
        normalize_id(listing.place_id)

      :composite_hash ->
        fields = opts[:composite_fields] || get_config(:composite_fields, [:cid, :place_id])
        generate_composite_hash(listing, fields)

      :custom ->
        hash_fn = opts[:hash_fn]
        if hash_fn, do: hash_fn.(listing), else: nil
    end
  end

  defp normalize_id(nil), do: nil
  defp normalize_id(""), do: nil
  defp normalize_id(id), do: id

  defp apply_prefix(nil, _prefix), do: nil
  defp apply_prefix(id, nil), do: id
  defp apply_prefix(id, prefix), do: "#{prefix}#{id}"

  defp generate_composite_hash(listing, fields) do
    # Collect field values in consistent order
    values =
      Enum.map_join(fields, "|", fn field ->
        case Map.get(listing, field) do
          nil -> ""
          value -> to_string(value)
        end
      end)

    # Return nil if all fields are empty
    if String.trim(values, "|") == "" do
      nil
    else
      # Generate SHA256 hash
      :crypto.hash(:sha256, values)
      |> Base.encode16(case: :lower)
      |> String.slice(0..31)
    end
  end
end
