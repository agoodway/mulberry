defmodule Mulberry.Document.FacebookProfile do
  @moduledoc """
  Facebook Profile document type for handling Facebook profiles from the ScrapeCreators API.

  This module provides a structured representation of Facebook profiles with comprehensive
  metadata and implements the Document protocol for text processing operations.
  """

  alias __MODULE__

  @type t :: %__MODULE__{
          # Core fields
          id: String.t() | nil,
          name: String.t() | nil,
          url: String.t() | nil,
          gender: String.t() | nil,

          # Cover photo
          cover_photo: map() | nil,

          # Profile photo
          profile_photo: map() | nil,

          # Business information
          is_business_page_active: boolean(),
          page_intro: String.t() | nil,
          category: String.t() | nil,
          address: String.t() | nil,
          email: String.t() | nil,
          links: [String.t()],
          phone: String.t() | nil,
          website: String.t() | nil,
          services: String.t() | nil,
          price_range: String.t() | nil,

          # Engagement metrics
          rating: String.t() | nil,
          rating_count: integer() | nil,
          like_count: integer() | nil,
          follower_count: integer() | nil,

          # Ad library
          ad_library: map() | nil,

          # Metadata
          creation_date: String.t() | nil,

          # Generated fields
          summary: String.t() | nil,
          keywords: [String.t()],

          # Extra metadata
          meta: keyword()
        }

  defstruct [
    # Core fields
    :id,
    :name,
    :url,
    :gender,

    # Cover photo
    :cover_photo,

    # Profile photo
    :profile_photo,

    # Business information
    :is_business_page_active,
    :page_intro,
    :category,
    :address,
    :email,
    :phone,
    :website,
    :services,
    :price_range,

    # Engagement metrics
    :rating,
    :rating_count,
    :like_count,
    :follower_count,

    # Ad library
    :ad_library,

    # Metadata
    :creation_date,

    # Generated fields
    :summary,

    # Fields with defaults (must come last)
    links: [],
    keywords: [],
    meta: []
  ]

  @doc """
  Creates a new FacebookProfile document struct with the given attributes.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    struct!(FacebookProfile, attrs)
  end

  defimpl Mulberry.Document do
    alias Mulberry.DocumentTransformer
    alias Mulberry.Text

    # Transform function - new unified interface
    @spec transform(FacebookProfile.t(), atom(), keyword()) ::
            {:ok, FacebookProfile.t()} | {:error, any(), FacebookProfile.t()}
    def transform(%FacebookProfile{} = profile, transformation, opts \\ []) do
      transformer = Keyword.get(opts, :transformer, DocumentTransformer.Default)
      transformer.transform(profile, transformation, opts)
    end

    @spec load(FacebookProfile.t(), keyword()) ::
            {:ok, FacebookProfile.t()} | {:error, any(), FacebookProfile.t()}
    def load(%FacebookProfile{} = profile, _opts) do
      # Facebook profiles come pre-loaded from the retriever
      # No additional loading is needed
      {:ok, profile}
    end

    @spec generate_summary(FacebookProfile.t(), keyword()) ::
            {:ok, FacebookProfile.t()} | {:error, any(), FacebookProfile.t()}
    def generate_summary(%FacebookProfile{} = profile, opts) do
      content = get_content_for_summary(profile)

      case Text.summarize(content, opts) do
        {:ok, summary} ->
          {:ok, %{profile | summary: summary}}

        {:error, error} ->
          {:error, error, profile}
      end
    end

    @spec generate_keywords(FacebookProfile.t(), keyword()) ::
            {:ok, FacebookProfile.t()} | {:error, any(), FacebookProfile.t()}
    def generate_keywords(%FacebookProfile{} = profile, _opts) do
      # Extract keywords from profile content
      keywords = extract_keywords(profile)
      {:ok, %{profile | keywords: keywords}}
    end

    @spec generate_title(FacebookProfile.t(), keyword()) ::
            {:ok, FacebookProfile.t()} | {:error, any(), FacebookProfile.t()}
    def generate_title(%FacebookProfile{} = profile, _opts) do
      # Facebook profiles already have names which serve as titles
      {:ok, profile}
    end

    @spec to_text(FacebookProfile.t(), keyword()) :: {:ok, String.t()} | {:error, any()}
    def to_text(%FacebookProfile{} = profile, _opts) do
      text = build_text_representation(profile)
      {:ok, text}
    end

    @spec to_tokens(FacebookProfile.t(), keyword()) :: {:ok, [String.t()]} | {:error, any()}
    def to_tokens(%FacebookProfile{} = profile, opts) do
      case to_text(profile, opts) do
        {:ok, text} ->
          case Text.tokens(text) do
            {:ok, tokens} -> {:ok, tokens}
            _ -> {:error, :tokenization_failed}
          end

        _ ->
          {:error, :tokenization_failed}
      end
    end

    @spec to_chunks(FacebookProfile.t(), keyword()) ::
            {:ok, [TextChunker.Chunk.t()]} | {:error, any()}
    def to_chunks(%FacebookProfile{} = profile, opts) do
      case to_text(profile, opts) do
        {:ok, text} ->
          chunks = Text.split(text)
          {:ok, chunks}

        error ->
          error
      end
    end

    @spec to_markdown(FacebookProfile.t(), keyword()) :: {:ok, String.t()} | {:error, any()}
    def to_markdown(%FacebookProfile{} = profile, _opts) do
      # Facebook profiles are structured data, return as markdown-formatted text
      text = build_markdown_representation(profile)
      {:ok, text}
    end

    # Private helper functions

    defp build_markdown_representation(%FacebookProfile{} = profile) do
      parts = [
        if(profile.name, do: "# #{profile.name}", else: "# Facebook Profile"),
        "",
        if(profile.category, do: "**Category:** #{profile.category}", else: nil),
        if(profile.page_intro && profile.page_intro != "",
          do: "\n#{profile.page_intro}\n",
          else: nil
        ),
        "",
        "---",
        "",
        format_md_contact_info(profile),
        format_md_business_details(profile),
        format_md_engagement_metrics(profile),
        "",
        if(profile.url, do: "**URL:** #{profile.url}", else: nil)
      ]

      parts
      |> Enum.filter(& &1)
      |> Enum.join("\n")
    end

    defp format_md_contact_info(profile) do
      parts = []
      parts = if profile.email, do: parts ++ ["- **Email:** #{profile.email}"], else: parts
      parts = if profile.phone, do: parts ++ ["- **Phone:** #{profile.phone}"], else: parts
      parts = if profile.website, do: parts ++ ["- **Website:** #{profile.website}"], else: parts
      parts = if profile.address, do: parts ++ ["- **Address:** #{profile.address}"], else: parts

      case parts do
        [] -> nil
        _ -> "## Contact\n" <> Enum.join(parts, "\n")
      end
    end

    defp format_md_business_details(profile) do
      parts = []

      parts =
        if profile.services, do: parts ++ ["- **Services:** #{profile.services}"], else: parts

      parts =
        if profile.price_range,
          do: parts ++ ["- **Price Range:** #{profile.price_range}"],
          else: parts

      case parts do
        [] -> nil
        _ -> "## Business\n" <> Enum.join(parts, "\n")
      end
    end

    defp format_md_engagement_metrics(profile) do
      parts = []

      parts =
        if profile.like_count,
          do: parts ++ ["- **Likes:** #{format_number(profile.like_count)}"],
          else: parts

      parts =
        if profile.follower_count,
          do: parts ++ ["- **Followers:** #{format_number(profile.follower_count)}"],
          else: parts

      parts = if profile.rating, do: parts ++ ["- **Rating:** #{profile.rating}"], else: parts

      case parts do
        [] -> nil
        _ -> "## Engagement\n" <> Enum.join(parts, "\n")
      end
    end

    defp get_content_for_summary(%FacebookProfile{} = profile) do
      parts = [
        if(profile.name, do: "Name: #{profile.name}", else: nil),
        if(profile.category, do: "Category: #{profile.category}", else: nil),
        if(profile.page_intro, do: "About: #{profile.page_intro}", else: nil),
        if(profile.services, do: "Services: #{profile.services}", else: nil),
        format_engagement_metrics(profile)
      ]

      parts
      |> Enum.filter(& &1)
      |> Enum.join("\n\n")
    end

    defp extract_keywords(%FacebookProfile{} = profile) do
      # Extract keywords from various fields
      keywords = []

      keywords = if profile.category, do: [profile.category | keywords], else: keywords

      keywords =
        if profile.services,
          do: extract_service_keywords(profile.services) ++ keywords,
          else: keywords

      Enum.uniq(keywords)
    end

    defp extract_service_keywords(services) do
      services
      |> String.split([",", ";", "|"])
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&(&1 != ""))
    end

    defp build_text_representation(%FacebookProfile{} = profile) do
      parts = [
        "=== Facebook Profile ===",
        format_basic_info(profile),
        format_business_category(profile),
        format_page_intro(profile),
        format_contact_info(profile),
        format_business_details(profile),
        format_engagement_metrics(profile),
        format_ad_library(profile),
        format_creation_date(profile)
      ]

      parts
      |> Enum.filter(& &1)
      |> Enum.join("\n")
    end

    defp format_basic_info(%{name: name, url: url}) when is_binary(name) do
      parts = ["Name: #{name}"]
      parts = if url, do: parts ++ ["URL: #{url}"], else: parts
      Enum.join(parts, "\n")
    end

    defp format_basic_info(_), do: nil

    defp format_business_category(%{category: category}) when is_binary(category),
      do: "Category: #{category}"

    defp format_business_category(_), do: nil

    defp format_page_intro(%{page_intro: intro}) when is_binary(intro) and intro != "",
      do: "\nAbout:\n#{intro}"

    defp format_page_intro(_), do: nil

    defp format_contact_info(profile) do
      parts = []
      parts = if profile.email, do: parts ++ ["Email: #{profile.email}"], else: parts
      parts = if profile.phone, do: parts ++ ["Phone: #{profile.phone}"], else: parts
      parts = if profile.website, do: parts ++ ["Website: #{profile.website}"], else: parts
      parts = if profile.address, do: parts ++ ["Address: #{profile.address}"], else: parts

      case parts do
        [] -> nil
        _ -> "\nContact Information:\n" <> Enum.join(parts, "\n")
      end
    end

    defp format_business_details(profile) do
      parts = []
      parts = if profile.services, do: parts ++ ["Services: #{profile.services}"], else: parts

      parts =
        if profile.price_range, do: parts ++ ["Price Range: #{profile.price_range}"], else: parts

      case parts do
        [] -> nil
        _ -> "\nBusiness Details:\n" <> Enum.join(parts, "\n")
      end
    end

    defp format_engagement_metrics(profile) do
      parts = []

      parts =
        if profile.like_count,
          do: parts ++ ["Likes: #{format_number(profile.like_count)}"],
          else: parts

      parts =
        if profile.follower_count,
          do: parts ++ ["Followers: #{format_number(profile.follower_count)}"],
          else: parts

      parts = if profile.rating, do: parts ++ ["Rating: #{profile.rating}"], else: parts

      case parts do
        [] -> nil
        _ -> "\nEngagement:\n" <> Enum.join(parts, "\n")
      end
    end

    defp format_ad_library(%{ad_library: %{"adStatus" => status}} = profile)
         when is_binary(status) do
      parts = ["Ad Status: #{status}"]

      updated_parts =
        if profile.ad_library["pageId"] do
          parts ++ ["Ad Library Page ID: #{profile.ad_library["pageId"]}"]
        else
          parts
        end

      "\nAdvertising:\n" <> Enum.join(updated_parts, "\n")
    end

    defp format_ad_library(_), do: nil

    defp format_creation_date(%{creation_date: date}) when is_binary(date),
      do: "\nPage Created: #{date}"

    defp format_creation_date(_), do: nil

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
