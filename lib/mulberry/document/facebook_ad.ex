defmodule Mulberry.Document.FacebookAd do
  @moduledoc """
  Facebook Ad document type for handling Facebook ads from the ScrapeCreators API.

  This module provides a structured representation of Facebook ads with comprehensive
  metadata and implements the Document protocol for text processing operations.
  """

  alias __MODULE__

  @type t :: %__MODULE__{
          # Core fields
          ad_archive_id: String.t(),
          ad_id: String.t() | nil,
          collation_id: String.t() | nil,
          collation_count: integer() | nil,

          # Page information
          page_id: String.t(),
          page_name: String.t(),
          page_is_deleted: boolean(),
          page_profile_uri: String.t() | nil,

          # Ad content
          body_text: String.t() | nil,
          caption: String.t() | nil,
          cta_text: String.t() | nil,
          cta_type: String.t() | nil,
          link_url: String.t() | nil,
          link_description: String.t() | nil,
          title: String.t() | nil,
          byline: String.t() | nil,

          # Media
          images: [map()] | nil,
          videos: [map()] | nil,
          display_format: String.t() | nil,

          # Metadata
          categories: [String.t()],
          entity_type: String.t() | nil,
          publisher_platform: [String.t()],
          currency: String.t() | nil,

          # Dates and status
          start_date: integer() | nil,
          end_date: integer() | nil,
          is_active: boolean(),

          # Targeting and reach
          targeted_or_reached_countries: [String.t()],
          impressions_text: String.t() | nil,
          impressions_index: integer() | nil,
          reach_estimate: map() | nil,

          # Compliance and reporting
          contains_sensitive_content: boolean(),
          has_user_reported: boolean(),
          report_count: integer() | nil,
          is_aaa_eligible: boolean(),

          # Generated fields
          summary: String.t() | nil,
          keywords: [String.t()],

          # Extra metadata
          meta: keyword()
        }

  defstruct [
    # Core fields
    :ad_archive_id,
    :ad_id,
    :collation_id,
    :collation_count,

    # Page information
    :page_id,
    :page_name,
    :page_is_deleted,
    :page_profile_uri,

    # Ad content
    :body_text,
    :caption,
    :cta_text,
    :cta_type,
    :link_url,
    :link_description,
    :title,
    :byline,

    # Media
    :display_format,

    # Metadata
    :entity_type,
    :currency,

    # Dates and status
    :start_date,
    :end_date,
    :is_active,

    # Targeting and reach
    :impressions_text,
    :impressions_index,
    :reach_estimate,

    # Compliance and reporting
    :contains_sensitive_content,
    :has_user_reported,
    :report_count,
    :is_aaa_eligible,

    # Generated fields
    :summary,

    # Fields with defaults (must come last)
    images: [],
    videos: [],
    categories: [],
    publisher_platform: [],
    targeted_or_reached_countries: [],
    keywords: [],
    meta: []
  ]

  @doc """
  Creates a new FacebookAd document struct with the given attributes.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    struct!(FacebookAd, attrs)
  end

  defimpl Mulberry.Document do
    alias Mulberry.DocumentTransformer
    alias Mulberry.Text

    @spec load(FacebookAd.t(), keyword()) ::
            {:ok, FacebookAd.t()} | {:error, any(), FacebookAd.t()}
    def load(%FacebookAd{} = ad, _opts) do
      # Facebook ads come pre-loaded from the search API
      # No additional loading is needed
      {:ok, ad}
    end

    # Transform function - new unified interface
    @spec transform(FacebookAd.t(), atom(), keyword()) ::
            {:ok, FacebookAd.t()} | {:error, any(), FacebookAd.t()}
    def transform(%FacebookAd{} = ad, transformation, opts \\ []) do
      transformer = Keyword.get(opts, :transformer, DocumentTransformer.FacebookAd)
      transformer.transform(ad, transformation, opts)
    end

    # Backward compatibility functions
    @spec generate_summary(FacebookAd.t(), keyword()) ::
            {:ok, FacebookAd.t()} | {:error, any(), FacebookAd.t()}
    def generate_summary(%FacebookAd{} = ad, opts \\ []) do
      transform(ad, :summary, opts)
    end

    @spec generate_keywords(FacebookAd.t(), keyword()) ::
            {:ok, FacebookAd.t()} | {:error, any(), FacebookAd.t()}
    def generate_keywords(%FacebookAd{} = ad, opts \\ []) do
      transform(ad, :keywords, opts)
    end

    @spec generate_title(FacebookAd.t(), keyword()) ::
            {:ok, FacebookAd.t()} | {:error, any(), FacebookAd.t()}
    def generate_title(%FacebookAd{} = ad, opts \\ []) do
      transform(ad, :title, opts)
    end

    @spec to_text(FacebookAd.t(), keyword()) :: {:ok, String.t()} | {:error, any()}
    def to_text(%FacebookAd{} = ad, _opts) do
      text = build_text_representation(ad)
      {:ok, text}
    end

    @spec to_tokens(FacebookAd.t(), keyword()) :: {:ok, [String.t()]} | {:error, any()}
    def to_tokens(%FacebookAd{} = ad, opts) do
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

    @spec to_chunks(FacebookAd.t(), keyword()) :: {:ok, [TextChunker.Chunk.t()]} | {:error, any()}
    def to_chunks(%FacebookAd{} = ad, opts) do
      case to_text(ad, opts) do
        {:ok, text} ->
          chunks = Text.split(text)
          {:ok, chunks}

        error ->
          error
      end
    end

    @spec to_markdown(FacebookAd.t(), keyword()) :: {:ok, String.t()} | {:error, any()}
    def to_markdown(%FacebookAd{} = ad, _opts) do
      # Facebook ads are structured data, return as markdown-formatted text
      text = build_markdown_representation(ad)
      {:ok, text}
    end

    # Private helper functions

    defp build_markdown_representation(%FacebookAd{} = ad) do
      parts = [
        "# Facebook Ad",
        "",
        format_md_advertiser(ad),
        format_md_title(ad),
        "",
        format_md_body(ad),
        "",
        format_md_description(ad),
        "",
        format_md_cta(ad),
        format_md_link(ad),
        "",
        "---",
        "",
        "**Platforms:** #{format_platforms(ad.publisher_platform)}",
        format_md_status(ad),
        format_md_impressions(ad),
        format_md_countries(ad)
      ]

      parts
      |> Enum.filter(& &1)
      |> Enum.join("\n")
    end

    defp format_md_advertiser(%{page_name: name}) when is_binary(name),
      do: "**Advertiser:** #{name}"

    defp format_md_advertiser(_), do: nil

    defp format_md_title(%{title: title}) when is_binary(title), do: "**Title:** #{title}"
    defp format_md_title(_), do: nil

    defp format_md_body(%{body_text: text}) when is_binary(text) and text != "", do: text
    defp format_md_body(_), do: nil

    defp format_md_description(%{link_description: desc}) when is_binary(desc), do: "> #{desc}"
    defp format_md_description(_), do: nil

    defp format_md_cta(%{cta_text: text, cta_type: type}) when is_binary(text) do
      "**Call to Action:** #{text} (#{type})"
    end

    defp format_md_cta(_), do: nil

    defp format_md_link(%{link_url: url}) when is_binary(url), do: "**Link:** #{url}"
    defp format_md_link(_), do: nil

    defp format_md_status(%{is_active: true}), do: "**Status:** Active"
    defp format_md_status(_), do: "**Status:** Inactive"

    defp format_md_impressions(%{impressions_text: text}) when is_binary(text) do
      "**Impressions:** #{text}"
    end

    defp format_md_impressions(_), do: nil

    defp format_md_countries(%{targeted_or_reached_countries: countries})
         when is_list(countries) and countries != [] do
      "**Countries:** #{Enum.join(countries, ", ")}"
    end

    defp format_md_countries(_), do: nil

    defp build_text_representation(%FacebookAd{} = ad) do
      parts = [
        "=== Facebook Ad ===",
        format_advertiser(ad),
        format_title(ad),
        format_body_text(ad),
        format_link_description(ad),
        format_cta(ad),
        format_link(ad),
        "\nPlatforms: #{format_platforms(ad.publisher_platform)}",
        "Status: #{if ad.is_active, do: "Active", else: "Inactive"}",
        format_impressions(ad),
        format_countries(ad)
      ]

      parts
      |> Enum.filter(& &1)
      |> Enum.join("\n")
    end

    defp format_advertiser(%{page_name: name}) when is_binary(name), do: "Advertiser: #{name}"
    defp format_advertiser(_), do: nil

    defp format_title(%{title: title}) when is_binary(title), do: "Title: #{title}"
    defp format_title(_), do: nil

    defp format_body_text(%{body_text: text}) when is_binary(text) and text != "", do: "\n#{text}"
    defp format_body_text(_), do: nil

    defp format_link_description(%{link_description: desc}) when is_binary(desc),
      do: "\nDescription: #{desc}"

    defp format_link_description(_), do: nil

    defp format_cta(%{cta_text: text, cta_type: type}) when is_binary(text),
      do: "\nCall to Action: #{text} (#{type})"

    defp format_cta(_), do: nil

    defp format_link(%{link_url: url}) when is_binary(url), do: "\nLink: #{url}"
    defp format_link(_), do: nil

    defp format_impressions(%{impressions_text: text}) when is_binary(text),
      do: "Impressions: #{text}"

    defp format_impressions(_), do: nil

    defp format_countries(%{targeted_or_reached_countries: countries})
         when is_list(countries) and countries != [],
         do: "Countries: #{Enum.join(countries, ", ")}"

    defp format_countries(_), do: nil

    defp format_platforms(nil), do: "Unknown"
    defp format_platforms([]), do: "Unknown"
    defp format_platforms(platforms), do: Enum.join(platforms, ", ")
  end
end
