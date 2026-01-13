defmodule Mulberry.Document.GoogleAd do
  @moduledoc """
  Google Ad document type for handling advertisement information from Google Ads transparency.

  This module provides a structured representation of Google ads with metadata about their
  display information and can be enriched with detailed variation data from the retriever.
  """

  alias __MODULE__

  @type t :: %__MODULE__{
          # Core identifiers
          advertiser_id: String.t() | nil,
          creative_id: String.t() | nil,

          # Ad information
          format: String.t() | nil,
          ad_url: String.t() | nil,
          advertiser_name: String.t() | nil,
          domain: String.t() | nil,

          # Time information
          first_shown: String.t() | nil,
          last_shown: String.t() | nil,

          # Detailed information (from retriever)
          overall_impressions: map() | nil,
          creative_regions: [map()],
          region_stats: [map()],
          variations: [map()],

          # Generated fields
          summary: String.t() | nil,
          keywords: [String.t()],

          # Extra metadata
          meta: keyword()
        }

  defstruct [
    # Core identifiers
    :advertiser_id,
    :creative_id,

    # Ad information
    :format,
    :ad_url,
    :advertiser_name,
    :domain,

    # Time information
    :first_shown,
    :last_shown,

    # Detailed information
    :overall_impressions,

    # Generated fields
    :summary,

    # Fields with defaults (must come last)
    creative_regions: [],
    region_stats: [],
    variations: [],
    keywords: [],
    meta: []
  ]

  @doc """
  Creates a new GoogleAd document struct with the given attributes.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    struct!(GoogleAd, attrs)
  end

  defimpl Mulberry.Document do
    require Logger
    alias Mulberry.Text
    alias Mulberry.Retriever.GoogleAd, as: GoogleAdRetriever
    alias Mulberry.DocumentTransformer

    @spec transform(GoogleAd.t(), atom(), keyword()) ::
            {:ok, GoogleAd.t()} | {:error, any(), GoogleAd.t()}
    def transform(%GoogleAd{} = ad, transformation, opts \\ []) do
      transformer = Keyword.get(opts, :transformer, DocumentTransformer.Default)
      transformer.transform(ad, transformation, opts)
    end

    @spec load(GoogleAd.t(), keyword()) ::
            {:ok, GoogleAd.t()} | {:error, any(), GoogleAd.t()}
    def load(%GoogleAd{ad_url: ad_url} = ad, opts) when is_binary(ad_url) do
      # If we have an ad URL, we can fetch additional details
      case GoogleAdRetriever.get(ad_url, opts) do
        {:ok, response} ->
          # Merge the detailed data with the existing ad
          detailed_ad = merge_detailed_data(ad, response.content)
          {:ok, detailed_ad}

        {:error, error} ->
          # Return the ad as-is if we can't load details
          Logger.warning("Failed to load Google ad details: #{inspect(error)}")
          {:ok, ad}
      end
    end

    def load(%GoogleAd{} = ad, _opts) do
      # No ad URL to load from
      {:ok, ad}
    end

    @spec generate_summary(GoogleAd.t(), keyword()) ::
            {:ok, GoogleAd.t()} | {:error, any(), GoogleAd.t()}
    def generate_summary(%GoogleAd{} = ad, opts) do
      content = get_content_for_summary(ad)

      case Text.summarize(content, opts) do
        {:ok, summary} ->
          {:ok, %{ad | summary: summary}}

        {:error, error} ->
          {:error, error, ad}
      end
    end

    @spec generate_keywords(GoogleAd.t(), keyword()) ::
            {:ok, GoogleAd.t()} | {:error, any(), GoogleAd.t()}
    def generate_keywords(%GoogleAd{} = ad, _opts) do
      keywords = extract_keywords(ad)
      {:ok, %{ad | keywords: keywords}}
    end

    @spec generate_title(GoogleAd.t(), keyword()) ::
            {:ok, GoogleAd.t()} | {:error, any(), GoogleAd.t()}
    def generate_title(%GoogleAd{} = ad, _opts) do
      # Google Ads don't have explicit titles, but we can generate one
      {:ok, ad}
    end

    @spec to_text(GoogleAd.t(), keyword()) :: {:ok, String.t()} | {:error, any()}
    def to_text(%GoogleAd{} = ad, _opts) do
      text = build_text_representation(ad)
      {:ok, text}
    end

    @spec to_tokens(GoogleAd.t(), keyword()) :: {:ok, [String.t()]} | {:error, any()}
    def to_tokens(%GoogleAd{} = ad, opts) do
      case to_text(ad, opts) do
        {:ok, text} ->
          case Text.tokens(text) do
            {:ok, tokens} -> {:ok, tokens}
            _ -> {:error, :tokenization_failed}
          end

        _ ->
          {:error, :tokenization_failed}
      end
    end

    @spec to_chunks(GoogleAd.t(), keyword()) ::
            {:ok, [TextChunker.Chunk.t()]} | {:error, any()}
    def to_chunks(%GoogleAd{} = ad, opts) do
      case to_text(ad, opts) do
        {:ok, text} ->
          chunks = Text.split(text)
          {:ok, chunks}

        error ->
          error
      end
    end

    @spec to_markdown(GoogleAd.t(), keyword()) :: {:ok, String.t()} | {:error, any()}
    def to_markdown(%GoogleAd{} = ad, _opts) do
      # Google ads are structured data, return as markdown-formatted text
      text = build_markdown_representation(ad)
      {:ok, text}
    end

    # Private helper functions

    defp build_markdown_representation(%GoogleAd{} = ad) do
      parts = [
        "# Google Ad",
        "",
        if(ad.advertiser_name, do: "**Advertiser:** #{ad.advertiser_name}", else: nil),
        if(ad.domain, do: "**Domain:** #{ad.domain}", else: nil),
        if(ad.format, do: "**Format:** #{ad.format}", else: nil),
        "",
        format_md_date_range(ad),
        format_md_impressions(ad),
        format_md_regions(ad),
        format_md_variations(ad)
      ]

      parts
      |> Enum.filter(& &1)
      |> Enum.join("\n")
    end

    defp format_md_date_range(%{first_shown: first, last_shown: last})
         when is_binary(first) or is_binary(last) do
      parts = ["## Date Range"]
      parts = if first, do: parts ++ ["- **First shown:** #{first}"], else: parts
      parts = if last, do: parts ++ ["- **Last shown:** #{last}"], else: parts
      Enum.join(parts, "\n")
    end

    defp format_md_date_range(_), do: nil

    defp format_md_impressions(%{overall_impressions: %{"min" => min, "max" => max}})
         when not is_nil(min) or not is_nil(max) do
      impression_text =
        case {min, max} do
          {nil, nil} -> "Unknown"
          {min, nil} -> "#{min}+"
          {nil, max} -> "Up to #{max}"
          {min, max} -> "#{min} - #{max}"
        end

      "**Overall Impressions:** #{impression_text}"
    end

    defp format_md_impressions(_), do: nil

    defp format_md_regions(%{creative_regions: regions}) when regions != [] do
      region_names =
        regions
        |> Enum.map(& &1["regionName"])
        |> Enum.filter(& &1)
        |> Enum.join(", ")

      if region_names != "", do: "**Regions:** #{region_names}", else: nil
    end

    defp format_md_regions(_), do: nil

    defp format_md_variations(%{variations: variations}) when variations != [] do
      parts = ["## Ad Variations"]

      variation_texts = Enum.map(variations, &format_md_single_variation/1)

      (parts ++ variation_texts)
      |> Enum.join("\n\n")
    end

    defp format_md_variations(_), do: nil

    defp format_md_single_variation(variation) do
      parts = []

      parts =
        if variation["headline"],
          do: parts ++ ["### #{variation["headline"]}"],
          else: parts

      parts =
        if variation["description"],
          do: parts ++ [variation["description"]],
          else: parts

      parts =
        if variation["destinationUrl"],
          do: parts ++ ["[View Ad](#{variation["destinationUrl"]})"],
          else: parts

      Enum.join(parts, "\n\n")
    end

    defp merge_detailed_data(ad, details) when is_map(details) do
      %{
        ad
        | overall_impressions: details["overallImpressions"],
          creative_regions: details["creativeRegions"] || [],
          region_stats: details["regionStats"] || [],
          variations: details["variations"] || []
      }
    end

    defp merge_detailed_data(ad, _), do: ad

    defp get_content_for_summary(%GoogleAd{} = ad) do
      parts = [
        if(ad.advertiser_name, do: "Advertiser: #{ad.advertiser_name}", else: nil),
        if(ad.domain, do: "Domain: #{ad.domain}", else: nil),
        if(ad.format, do: "Format: #{ad.format}", else: nil),
        format_date_range(ad),
        format_variations(ad),
        format_regions(ad)
      ]

      parts
      |> Enum.filter(& &1)
      |> Enum.join("\n\n")
    end

    defp extract_keywords(%GoogleAd{} = ad) do
      keywords = []

      # Add format as keyword
      keywords = if ad.format, do: [ad.format | keywords], else: keywords

      # Extract keywords from variations
      keywords = keywords ++ extract_variation_keywords(ad.variations)

      # Add regions as keywords
      keywords = keywords ++ extract_region_keywords(ad.creative_regions)

      Enum.uniq(keywords)
    end

    defp extract_variation_keywords(variations) do
      variations
      |> Enum.flat_map(fn var ->
        headline = var["headline"] || ""

        headline
        |> String.split([" ", "-", "|"])
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&(String.length(&1) > 3))
      end)
      |> Enum.uniq()
    end

    defp extract_region_keywords(regions) do
      regions
      |> Enum.map(& &1["regionName"])
      |> Enum.filter(& &1)
      |> Enum.uniq()
    end

    defp build_text_representation(%GoogleAd{} = ad) do
      parts = [
        "=== Google Ad ===",
        format_basic_info(ad),
        format_advertiser_info(ad),
        format_date_range(ad),
        format_impressions(ad),
        format_regions(ad),
        format_variations(ad)
      ]

      parts
      |> Enum.filter(& &1)
      |> Enum.join("\n")
    end

    defp format_basic_info(ad) do
      parts = []
      parts = if ad.creative_id, do: parts ++ ["Creative ID: #{ad.creative_id}"], else: parts

      parts =
        if ad.advertiser_id, do: parts ++ ["Advertiser ID: #{ad.advertiser_id}"], else: parts

      parts = if ad.format, do: parts ++ ["Format: #{ad.format}"], else: parts

      case parts do
        [] -> nil
        _ -> Enum.join(parts, "\n")
      end
    end

    defp format_advertiser_info(ad) do
      parts = []

      parts =
        if ad.advertiser_name, do: parts ++ ["Advertiser: #{ad.advertiser_name}"], else: parts

      parts = if ad.domain, do: parts ++ ["Domain: #{ad.domain}"], else: parts

      case parts do
        [] -> nil
        _ -> "\n" <> Enum.join(parts, "\n")
      end
    end

    defp format_date_range(%{first_shown: first, last_shown: last})
         when is_binary(first) or is_binary(last) do
      parts = ["\nDate Range:"]
      parts = if first, do: parts ++ ["First shown: #{first}"], else: parts
      parts = if last, do: parts ++ ["Last shown: #{last}"], else: parts
      Enum.join(parts, "\n")
    end

    defp format_date_range(_), do: nil

    defp format_impressions(%{overall_impressions: %{"min" => min, "max" => max}})
         when not is_nil(min) or not is_nil(max) do
      impression_text =
        case {min, max} do
          {nil, nil} -> "Unknown"
          {min, nil} -> "#{min}+"
          {nil, max} -> "Up to #{max}"
          {min, max} -> "#{min} - #{max}"
        end

      "\nOverall Impressions: #{impression_text}"
    end

    defp format_impressions(_), do: nil

    defp format_regions(%{creative_regions: regions}) when regions != [] do
      region_names =
        regions
        |> Enum.map(& &1["regionName"])
        |> Enum.filter(& &1)
        |> Enum.join(", ")

      if region_names != "", do: "\nRegions: #{region_names}", else: nil
    end

    defp format_regions(_), do: nil

    defp format_variations(%{variations: variations}) when variations != [] do
      parts = ["\nAd Variations:"]

      variation_texts = Enum.map(variations, &format_single_variation/1)

      (parts ++ variation_texts)
      |> Enum.join("\n")
    end

    defp format_variations(_), do: nil

    defp format_single_variation(variation) do
      parts = ["---"]

      parts =
        if variation["headline"],
          do: parts ++ ["Headline: #{variation["headline"]}"],
          else: parts

      parts =
        if variation["description"],
          do: parts ++ ["Description: #{variation["description"]}"],
          else: parts

      parts =
        if variation["destinationUrl"],
          do: parts ++ ["Destination: #{variation["destinationUrl"]}"],
          else: parts

      Enum.join(parts, "\n")
    end
  end
end
