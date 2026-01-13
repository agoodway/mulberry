defmodule Mulberry.Document.FacebookAdCompany do
  @moduledoc """
  Facebook Ad Company document type for handling company information from Facebook Ad Library searches.

  This module provides a structured representation of companies found in Facebook's Ad Library
  with metadata about their advertising presence and social media profiles.
  """

  alias __MODULE__

  @type t :: %__MODULE__{
          # Core fields
          page_id: String.t() | nil,
          name: String.t() | nil,
          category: String.t() | nil,

          # Visual
          image_uri: String.t() | nil,

          # Engagement metrics
          likes: integer() | nil,
          verification: String.t() | nil,

          # Location
          country: String.t() | nil,

          # Entity information
          entity_type: String.t() | nil,
          page_alias: String.t() | nil,
          page_is_deleted: boolean(),

          # Instagram integration
          ig_username: String.t() | nil,
          ig_followers: integer() | nil,
          ig_verification: boolean(),

          # Generated fields
          summary: String.t() | nil,
          keywords: [String.t()],

          # Extra metadata
          meta: keyword()
        }

  defstruct [
    # Core fields
    :page_id,
    :name,
    :category,

    # Visual
    :image_uri,

    # Engagement metrics
    :likes,
    :verification,

    # Location
    :country,

    # Entity information
    :entity_type,
    :page_alias,

    # Instagram integration
    :ig_username,
    :ig_followers,

    # Generated fields
    :summary,

    # Fields with defaults (must come last)
    page_is_deleted: false,
    ig_verification: false,
    keywords: [],
    meta: []
  ]

  @doc """
  Creates a new FacebookAdCompany document struct with the given attributes.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    struct!(FacebookAdCompany, attrs)
  end

  defimpl Mulberry.Document do
    alias Mulberry.DocumentTransformer
    alias Mulberry.Text

    # Transform function - new unified interface
    @spec transform(FacebookAdCompany.t(), atom(), keyword()) ::
            {:ok, FacebookAdCompany.t()} | {:error, any(), FacebookAdCompany.t()}
    def transform(%FacebookAdCompany{} = company, transformation, opts \\ []) do
      transformer = Keyword.get(opts, :transformer, DocumentTransformer.Default)
      transformer.transform(company, transformation, opts)
    end

    @spec load(FacebookAdCompany.t(), keyword()) ::
            {:ok, FacebookAdCompany.t()} | {:error, any(), FacebookAdCompany.t()}
    def load(%FacebookAdCompany{} = company, _opts) do
      # Facebook Ad Companies come pre-loaded from the search API
      # No additional loading is needed
      {:ok, company}
    end

    @spec generate_summary(FacebookAdCompany.t(), keyword()) ::
            {:ok, FacebookAdCompany.t()} | {:error, any(), FacebookAdCompany.t()}
    def generate_summary(%FacebookAdCompany{} = company, opts) do
      content = get_content_for_summary(company)

      case Text.summarize(content, opts) do
        {:ok, summary} ->
          {:ok, %{company | summary: summary}}

        {:error, error} ->
          {:error, error, company}
      end
    end

    @spec generate_keywords(FacebookAdCompany.t(), keyword()) ::
            {:ok, FacebookAdCompany.t()} | {:error, any(), FacebookAdCompany.t()}
    def generate_keywords(%FacebookAdCompany{} = company, _opts) do
      # Extract keywords from company data
      keywords = extract_keywords(company)
      {:ok, %{company | keywords: keywords}}
    end

    @spec generate_title(FacebookAdCompany.t(), keyword()) ::
            {:ok, FacebookAdCompany.t()} | {:error, any(), FacebookAdCompany.t()}
    def generate_title(%FacebookAdCompany{} = company, _opts) do
      # Facebook Ad Companies already have names which serve as titles
      {:ok, company}
    end

    @spec to_text(FacebookAdCompany.t(), keyword()) :: {:ok, String.t()} | {:error, any()}
    def to_text(%FacebookAdCompany{} = company, _opts) do
      text = build_text_representation(company)
      {:ok, text}
    end

    @spec to_tokens(FacebookAdCompany.t(), keyword()) :: {:ok, [String.t()]} | {:error, any()}
    def to_tokens(%FacebookAdCompany{} = company, opts) do
      case to_text(company, opts) do
        {:ok, text} ->
          case Text.tokens(text) do
            {:ok, tokens} -> {:ok, tokens}
            _ -> {:error, :tokenization_failed}
          end

        _ ->
          {:error, :tokenization_failed}
      end
    end

    @spec to_chunks(FacebookAdCompany.t(), keyword()) ::
            {:ok, [TextChunker.Chunk.t()]} | {:error, any()}
    def to_chunks(%FacebookAdCompany{} = company, opts) do
      case to_text(company, opts) do
        {:ok, text} ->
          chunks = Text.split(text)
          {:ok, chunks}

        error ->
          error
      end
    end

    @spec to_markdown(FacebookAdCompany.t(), keyword()) :: {:ok, String.t()} | {:error, any()}
    def to_markdown(%FacebookAdCompany{} = company, _opts) do
      # Facebook Ad Companies are structured data, return as markdown-formatted text
      text = build_markdown_representation(company)
      {:ok, text}
    end

    # Private helper functions

    defp build_markdown_representation(%FacebookAdCompany{} = company) do
      parts = [
        if(company.name, do: "# #{company.name}", else: "# Facebook Ad Company"),
        "",
        if(company.category, do: "**Category:** #{company.category}", else: nil),
        if(company.entity_type, do: "**Entity Type:** #{company.entity_type}", else: nil),
        if(company.verification, do: "**Verification:** #{company.verification}", else: nil),
        "",
        format_md_social_presence(company),
        format_md_instagram_presence(company),
        "",
        if(company.country, do: "**Location:** #{company.country}", else: nil),
        if(company.page_is_deleted, do: "*Page Status: Deleted*", else: nil)
      ]

      parts
      |> Enum.filter(& &1)
      |> Enum.join("\n")
    end

    defp format_md_social_presence(%{likes: likes}) when is_integer(likes) and likes > 0 do
      "## Facebook Presence\n- **Likes:** #{format_number(likes)}"
    end

    defp format_md_social_presence(_), do: nil

    defp format_md_instagram_presence(company) do
      if company.ig_username do
        parts = ["## Instagram Presence"]
        parts = parts ++ ["- **Username:** @#{company.ig_username}"]

        parts =
          if company.ig_followers,
            do: parts ++ ["- **Followers:** #{format_number(company.ig_followers)}"],
            else: parts

        parts =
          if company.ig_verification,
            do: parts ++ ["- **Verified:** Yes"],
            else: parts

        Enum.join(parts, "\n")
      end
    end

    defp get_content_for_summary(%FacebookAdCompany{} = company) do
      parts = [
        if(company.name, do: "Company: #{company.name}", else: nil),
        if(company.category, do: "Category: #{company.category}", else: nil),
        format_verification_status(company),
        format_social_presence(company),
        format_location(company)
      ]

      parts
      |> Enum.filter(& &1)
      |> Enum.join("\n\n")
    end

    defp extract_keywords(%FacebookAdCompany{} = company) do
      keywords = []

      keywords = if company.category, do: [company.category | keywords], else: keywords
      keywords = if company.entity_type, do: [company.entity_type | keywords], else: keywords
      keywords = if company.country, do: [company.country | keywords], else: keywords

      # Add verification status as keyword if verified
      keywords =
        if company.verification in ["BLUE_VERIFIED", "VERIFIED"],
          do: ["Verified" | keywords],
          else: keywords

      Enum.uniq(keywords)
    end

    defp build_text_representation(%FacebookAdCompany{} = company) do
      parts = [
        "=== Facebook Ad Company ===",
        format_basic_info(company),
        format_category_and_type(company),
        format_verification_status(company),
        format_social_presence(company),
        format_instagram_presence(company),
        format_location(company),
        format_page_status(company)
      ]

      parts
      |> Enum.filter(& &1)
      |> Enum.join("\n")
    end

    defp format_basic_info(%{name: name, page_id: page_id}) when is_binary(name) do
      parts = ["Name: #{name}"]
      parts = if page_id, do: parts ++ ["Page ID: #{page_id}"], else: parts
      Enum.join(parts, "\n")
    end

    defp format_basic_info(_), do: nil

    defp format_category_and_type(company) do
      parts = []
      parts = if company.category, do: parts ++ ["Category: #{company.category}"], else: parts

      parts =
        if company.entity_type, do: parts ++ ["Entity Type: #{company.entity_type}"], else: parts

      case parts do
        [] -> nil
        _ -> Enum.join(parts, "\n")
      end
    end

    defp format_verification_status(%{verification: verification}) when is_binary(verification) do
      "Verification: #{verification}"
    end

    defp format_verification_status(_), do: nil

    defp format_social_presence(%{likes: likes}) when is_integer(likes) and likes > 0 do
      "\nFacebook Presence:\nLikes: #{format_number(likes)}"
    end

    defp format_social_presence(_), do: nil

    defp format_instagram_presence(company) do
      if company.ig_username do
        parts = ["Username: @#{company.ig_username}"]

        parts =
          if company.ig_followers,
            do: parts ++ ["Followers: #{format_number(company.ig_followers)}"],
            else: parts

        parts =
          if company.ig_verification,
            do: parts ++ ["Verified: Yes"],
            else: parts

        "\nInstagram Presence:\n" <> Enum.join(parts, "\n")
      end
    end

    defp format_location(%{country: country}) when is_binary(country),
      do: "\nLocation: #{country}"

    defp format_location(_), do: nil

    defp format_page_status(%{page_is_deleted: true}),
      do: "\nPage Status: Deleted"

    defp format_page_status(%{page_alias: alias}) when is_binary(alias),
      do: "\nPage Alias: #{alias}"

    defp format_page_status(_), do: nil

    defp format_number(num) when is_integer(num) do
      num
      |> Integer.to_string()
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.join(",")
      |> String.reverse()
    end

    defp format_number(num), do: to_string(num)
  end
end
