defmodule DataForSEO.Schemas.GoogleOrganicItem do
  @moduledoc """
  Schema for individual organic search result items from DataForSEO Google Organic SERP API.

  Represents a single organic search result with positioning, content, and optional
  rich features like ratings, sitelinks, FAQs, and images.

  ## Fields

  ### Core Content
  - `:title` - Result title/headline
  - `:url` - Direct link to the result page
  - `:description` - Snippet/preview text from the page
  - `:domain` - Source domain of the result
  - `:breadcrumb` - Navigation breadcrumb path (if available)
  - `:cache_url` - Link to Google's cached version

  ### Positioning
  - `:rank_group` - Group ranking position
  - `:rank_absolute` - Absolute position across all SERP elements
  - `:position` - Position within the result set
  - `:xpath` - DOM location path

  ### Metadata
  - `:type` - Result type (always "organic" for standard results)
  - `:is_image` - Contains image content
  - `:is_video` - Contains video content
  - `:is_featured_snippet` - Is a featured snippet
  - `:is_malicious` - Flagged as potentially malicious
  - `:is_web_story` - Is a Web Story format
  - `:amp_version` - Has AMP version available

  ### Rich Features (optional nested objects)
  - `:rating` - User rating information (value, votes, max)
  - `:price` - Price information for products
  - `:faq` - FAQ extension with questions and answers
  - `:sitelinks` - Additional site navigation links
  - `:images` - Image attachments in the result

  ## Examples

      iex> item = %DataForSEO.Schemas.GoogleOrganicItem{
      ...>   title: "Example Page",
      ...>   url: "https://example.com/page",
      ...>   domain: "example.com",
      ...>   position: 1
      ...> }
      %DataForSEO.Schemas.GoogleOrganicItem{title: "Example Page", ...}

  """

  @type rating :: %{
          type: String.t() | nil,
          value: float() | nil,
          votes: integer() | nil,
          rating_max: integer() | nil
        }

  @type price :: %{
          current: String.t() | float() | nil,
          regular: String.t() | float() | nil,
          currency: String.t() | nil,
          currency_iso_code: String.t() | nil,
          displayed_price: String.t() | nil
        }

  @type faq_item :: %{
          question: String.t() | nil,
          answer: String.t() | nil
        }

  @type sitelink :: %{
          title: String.t() | nil,
          url: String.t() | nil,
          description: String.t() | nil
        }

  @type image_item :: %{
          alt: String.t() | nil,
          url: String.t() | nil
        }

  @type t :: %__MODULE__{
          title: String.t() | nil,
          url: String.t() | nil,
          description: String.t() | nil,
          domain: String.t() | nil,
          breadcrumb: String.t() | nil,
          cache_url: String.t() | nil,
          rank_group: integer() | nil,
          rank_absolute: integer() | nil,
          position: integer() | nil,
          xpath: String.t() | nil,
          type: String.t() | nil,
          is_image: boolean() | nil,
          is_video: boolean() | nil,
          is_featured_snippet: boolean() | nil,
          is_malicious: boolean() | nil,
          is_web_story: boolean() | nil,
          amp_version: boolean() | nil,
          rating: rating() | nil,
          price: price() | nil,
          faq: faq_item() | nil,
          sitelinks: [sitelink()],
          images: [image_item()]
        }

  defstruct [
    :title,
    :url,
    :description,
    :domain,
    :breadcrumb,
    :cache_url,
    :rank_group,
    :rank_absolute,
    :position,
    :xpath,
    :type,
    :is_image,
    :is_video,
    :is_featured_snippet,
    :is_malicious,
    :is_web_story,
    :amp_version,
    :rating,
    :price,
    :faq,
    sitelinks: [],
    images: []
  ]

  @doc """
  Creates a GoogleOrganicItem struct from a map of attributes.

  Parses the result item data from the DataForSEO API response and converts
  nested structures (rating, price, faq, sitelinks, images) into maps.

  ## Parameters

  - `attrs` - Map containing the result item data from the API response

  ## Returns

  A `GoogleOrganicItem` struct with parsed nested structures.

  ## Examples

      iex> DataForSEO.Schemas.GoogleOrganicItem.new(%{
      ...>   "title" => "Best Product",
      ...>   "url" => "https://example.com/product",
      ...>   "domain" => "example.com",
      ...>   "rating" => %{"value" => 4.5, "votes" => 120}
      ...> })
      %DataForSEO.Schemas.GoogleOrganicItem{
        title: "Best Product",
        url: "https://example.com/product",
        rating: %{value: 4.5, votes: 120, ...}
      }

  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      title: attrs["title"],
      url: attrs["url"],
      description: attrs["description"],
      domain: attrs["domain"],
      breadcrumb: attrs["breadcrumb"],
      cache_url: attrs["cache_url"],
      rank_group: attrs["rank_group"],
      rank_absolute: attrs["rank_absolute"],
      position: attrs["position"],
      xpath: attrs["xpath"],
      type: attrs["type"],
      is_image: attrs["is_image"],
      is_video: attrs["is_video"],
      is_featured_snippet: attrs["is_featured_snippet"],
      is_malicious: attrs["is_malicious"],
      is_web_story: attrs["is_web_story"],
      amp_version: attrs["amp_version"],
      rating: parse_rating(attrs["rating"]),
      price: parse_price(attrs["price"]),
      faq: parse_faq(attrs["faq"]),
      sitelinks: parse_sitelinks(attrs["links"]),
      images: parse_images(attrs["images"])
    }
  end

  @doc """
  Checks if the organic result has a rating.

  ## Parameters

  - `item` - A `GoogleOrganicItem` struct

  ## Returns

  Boolean indicating if the item has rating information.

  ## Examples

      iex> item = %DataForSEO.Schemas.GoogleOrganicItem{rating: %{value: 4.5}}
      iex> DataForSEO.Schemas.GoogleOrganicItem.has_rating?(item)
      true

  """
  @spec has_rating?(t()) :: boolean()
  def has_rating?(%__MODULE__{rating: rating}), do: not is_nil(rating)

  @doc """
  Checks if the organic result has sitelinks.

  ## Parameters

  - `item` - A `GoogleOrganicItem` struct

  ## Returns

  Boolean indicating if the item has sitelinks.

  ## Examples

      iex> item = %DataForSEO.Schemas.GoogleOrganicItem{sitelinks: [%{title: "About"}]}
      iex> DataForSEO.Schemas.GoogleOrganicItem.has_sitelinks?(item)
      true

  """
  @spec has_sitelinks?(t()) :: boolean()
  def has_sitelinks?(%__MODULE__{sitelinks: sitelinks}), do: length(sitelinks) > 0

  @doc """
  Checks if the organic result has images.

  ## Parameters

  - `item` - A `GoogleOrganicItem` struct

  ## Returns

  Boolean indicating if the item has images.

  ## Examples

      iex> item = %DataForSEO.Schemas.GoogleOrganicItem{images: [%{url: "..."}]}
      iex> DataForSEO.Schemas.GoogleOrganicItem.has_images?(item)
      true

  """
  @spec has_images?(t()) :: boolean()
  def has_images?(%__MODULE__{images: images}), do: length(images) > 0

  # Private helpers

  defp parse_rating(nil), do: nil

  defp parse_rating(rating) when is_map(rating) do
    %{
      type: rating["type"] || rating["rating_type"],
      value: rating["value"],
      votes: rating["votes_count"] || rating["votes"],
      rating_max: rating["rating_max"]
    }
  end

  defp parse_price(nil), do: nil

  defp parse_price(price) when is_map(price) do
    %{
      current: price["current"] || price["price_current"],
      regular: price["regular"] || price["price_regular"],
      currency: price["currency"],
      currency_iso_code: price["currency_iso_code"],
      displayed_price: price["displayed_price"]
    }
  end

  defp parse_faq(nil), do: nil

  defp parse_faq(faq) when is_map(faq) do
    %{
      question: faq["question"],
      answer: faq["answer"]
    }
  end

  defp parse_sitelinks(nil), do: []

  defp parse_sitelinks(links) when is_list(links) do
    Enum.map(links, fn link ->
      %{
        title: link["title"],
        url: link["url"],
        description: link["description"]
      }
    end)
  end

  defp parse_images(nil), do: []

  defp parse_images(images) when is_list(images) do
    Enum.map(images, fn image ->
      %{
        alt: image["alt"],
        url: image["url"] || image["image_url"]
      }
    end)
  end
end
