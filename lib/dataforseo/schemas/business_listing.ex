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

  @doc """
  Fetches Google reviews for this business listing.

  Starts an async task to fetch reviews using this business's CID or place_id.
  Prefers CID if available (more stable and lower cost for extended reviews).

  ## Parameters

  - `listing` - The BusinessListing struct
  - `opts` - Options keyword list (optional)

  ## Options

  - `:depth` - Number of reviews to fetch (default: 10, max: 4490)
  - `:sort_by` - Sort order: "newest", "highest_rating", "lowest_rating", "relevant"
  - `:language_code` - Language code (default: "en")
  - `:callback` - Function called when results ready
  - `:extended` - Use extended reviews (default: false)

  ## Returns

  - `{:ok, pid}` - Task manager PID
  - `{:error, reason}` - Error if task cannot be started

  ## Examples

      iex> business = %BusinessListing{cid: "12345"}
      iex> {:ok, pid} = BusinessListing.fetch_reviews(business, depth: 100, sort_by: "newest")

      iex> business = %BusinessListing{place_id: "ChIJ123"}
      iex> BusinessListing.fetch_reviews(business,
      ...>   depth: 50,
      ...>   callback: fn {:ok, reviews} -> IO.inspect(reviews.reviews_count) end
      ...> )

  """
  @spec fetch_reviews(t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def fetch_reviews(listing, opts \\ []) do
    extended = Keyword.get(opts, :extended, false)

    task_module =
      if extended do
        DataForSEO.Tasks.ExtendedGoogleReviews
      else
        DataForSEO.Tasks.GoogleReviews
      end

    task_params = build_reviews_params(listing, opts)

    # Extract supervisor options (callback, poll_interval, timeout, task_id)
    supervisor_opts = Keyword.take(opts, [:callback, :poll_interval_ms, :timeout_ms, :task_id])

    DataForSEO.Supervisor.start_task(task_module, task_params, supervisor_opts)
  end

  @doc """
  Fetches extended Google reviews (multi-platform) for this business listing.

  Convenience function equivalent to `fetch_reviews(listing, [extended: true] ++ opts)`.
  Returns reviews from Google plus other platforms like TripAdvisor, Yelp, etc.

  ## Parameters

  - `listing` - The BusinessListing struct
  - `opts` - Options keyword list (optional)

  ## Options

  Same as `fetch_reviews/2` (depth, sort_by, language_code, callback)

  ## Returns

  - `{:ok, pid}` - Task manager PID
  - `{:error, reason}` - Error if task cannot be started

  ## Examples

      iex> business = %BusinessListing{cid: "12345"}
      iex> {:ok, pid} = BusinessListing.fetch_extended_reviews(business, depth: 100)

  """
  @spec fetch_extended_reviews(t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def fetch_extended_reviews(listing, opts \\ []) do
    fetch_reviews(listing, Keyword.put(opts, :extended, true))
  end

  # Private helper for building reviews task params
  defp build_reviews_params(listing, opts) do
    # Prefer CID (more stable, lower cost for extended reviews)
    base_params =
      cond do
        listing.cid -> %{cid: listing.cid}
        listing.place_id -> %{place_id: listing.place_id}
        true -> %{}
      end

    # Add optional parameters
    base_params
    |> maybe_put_param(:depth, opts[:depth])
    |> maybe_put_param(:sort_by, opts[:sort_by])
    |> maybe_put_param(:language_code, opts[:language_code])
    |> maybe_put_param(:tag, opts[:tag])
  end

  defp maybe_put_param(map, _key, nil), do: map
  defp maybe_put_param(map, key, value), do: Map.put(map, key, value)
end
