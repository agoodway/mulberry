defmodule Mulberry.Search.FacebookAds do
  @behaviour Mulberry.Search.Behaviour
  @moduledoc """
  Facebook Ads search using ScrapeCreators API

  Provides search functionality for Facebook ads with comprehensive metadata extraction.

  ## Configuration

  Requires the `SCRAPECREATORS_API_KEY` environment variable or `:scrapecreators_api_key` in config.

  ## Examples

      # Search by company name
      {:ok, ads} = Mulberry.search(Mulberry.Search.FacebookAds, "Nike")
      
      # Search by page ID
      {:ok, response} = Mulberry.Search.FacebookAds.search("12345", 20,
        search_by: :page_id,
        country: "US",
        status: "ACTIVE",
        media_type: "image"
      )
      {:ok, ads} = Mulberry.Search.FacebookAds.to_documents(response)
      
      # Access Facebook-specific fields
      ad = List.first(ads)
      ad.page_name               # => "Nike"
      ad.cta_text                # => "Shop Now"
      ad.is_active               # => true
      ad.publisher_platform      # => ["FACEBOOK", "INSTAGRAM"]
      
      # Pagination
      {:ok, response} = Mulberry.Search.FacebookAds.search("Apple", 20)
      {:ok, ads} = Mulberry.Search.FacebookAds.to_documents(response)
      cursor = response["cursor"]
      
      # Get next page
      {:ok, next_response} = Mulberry.Search.FacebookAds.search("Apple", 20, cursor: cursor)

  ## API Reference

  https://api.scrapecreators.com/v1/facebook/adLibrary/company/ads
  """

  require Logger

  @facebook_ads_url "https://api.scrapecreators.com/v1/facebook/adLibrary/company/ads"

  @impl true
  @spec search(binary(), pos_integer(), keyword()) :: {:ok, map()} | {:error, binary()}
  def search(query, _count \\ 20, opts \\ []) do
    retriever = Keyword.get(opts, :retriever, Mulberry.Retriever.Req)

    # Determine if we're searching by page_id or company_name
    search_by = Keyword.get(opts, :search_by, :company_name)

    # Build parameters
    params = build_params(query, search_by, opts)

    request_opts = [
      params: params,
      headers: [
        {"x-api-key", Mulberry.config(:scrapecreators_api_key)}
      ]
    ]

    case Mulberry.Retriever.get(retriever, @facebook_ads_url, request_opts) do
      {:ok, response} -> {:ok, response.content}
      {:error, _} = error -> error
    end
  end

  @impl true
  @spec to_documents(any()) :: {:ok, [Mulberry.Document.FacebookAd.t()]} | {:error, atom()}
  def to_documents(results) do
    case results do
      %{"results" => ads} when is_list(ads) ->
        docs = Enum.map(ads, &facebook_ad_to_document/1)
        {:ok, docs}

      %{"results" => []} ->
        {:ok, []}

      %{"error" => error} ->
        Logger.error("#{__MODULE__}.to_documents/1 Facebook ads search failed: #{inspect(error)}")
        {:error, :search_failed}

      response ->
        Logger.error(
          "#{__MODULE__}.to_documents/1 unexpected response format: #{inspect(response)}"
        )

        {:error, :parse_search_results_failed}
    end
  end

  defp build_params(query, search_by, opts) do
    # Start with the search parameter
    params =
      case search_by do
        :page_id -> %{pageId: query}
        _ -> %{companyName: query}
      end

    # Add optional parameters
    params
    |> maybe_add_param(:country, Keyword.get(opts, :country))
    |> maybe_add_param(:status, Keyword.get(opts, :status))
    |> maybe_add_param(:media_type, Keyword.get(opts, :media_type))
    |> maybe_add_param(:cursor, Keyword.get(opts, :cursor))
    |> maybe_add_param(:trim, Keyword.get(opts, :trim))
  end

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: Map.put(params, key, value)

  defp facebook_ad_to_document(ad) do
    snapshot = ad["snapshot"] || %{}

    attrs =
      %{}
      |> Map.merge(extract_core_fields(ad))
      |> Map.merge(extract_page_info(ad, snapshot))
      |> Map.merge(extract_ad_content(snapshot))
      |> Map.merge(extract_media(snapshot))
      |> Map.merge(extract_metadata(ad))
      |> Map.merge(extract_dates_and_status(ad))
      |> Map.merge(extract_targeting_and_reach(ad))
      |> Map.merge(extract_compliance_data(ad))

    Mulberry.Document.FacebookAd.new(attrs)
  end

  defp extract_core_fields(ad) do
    %{
      ad_archive_id: ad["ad_archive_id"],
      ad_id: ad["ad_id"],
      collation_id: ad["collation_id"],
      collation_count: ad["collation_count"]
    }
  end

  defp extract_page_info(ad, snapshot) do
    branded_content = snapshot["branded_content"] || %{}

    %{
      page_id: ad["page_id"],
      page_name: ad["page_name"],
      page_is_deleted: ad["page_is_deleted"],
      page_profile_uri: branded_content["page_profile_uri"]
    }
  end

  defp extract_ad_content(snapshot) do
    %{
      body_text: extract_body_text(snapshot),
      caption: snapshot["caption"],
      cta_text: snapshot["cta_text"],
      cta_type: snapshot["cta_type"],
      link_url: snapshot["link_url"],
      link_description: snapshot["link_description"],
      title: snapshot["title"],
      byline: snapshot["byline"]
    }
  end

  defp extract_media(snapshot) do
    %{
      images: snapshot["images"] || [],
      videos: snapshot["videos"] || [],
      display_format: snapshot["display_format"]
    }
  end

  defp extract_metadata(ad) do
    %{
      categories: ad["categories"] || [],
      entity_type: ad["entity_type"],
      publisher_platform: ad["publisher_platform"] || [],
      currency: ad["currency"]
    }
  end

  defp extract_dates_and_status(ad) do
    %{
      start_date: ad["start_date"],
      end_date: ad["end_date"],
      is_active: ad["is_active"] || false
    }
  end

  defp extract_targeting_and_reach(ad) do
    impressions = ad["impressions_with_index"] || %{}

    %{
      targeted_or_reached_countries: ad["targeted_or_reached_countries"] || [],
      impressions_text: impressions["impressions_text"],
      impressions_index: impressions["impressions_index"],
      reach_estimate: ad["reach_estimate"]
    }
  end

  defp extract_compliance_data(ad) do
    %{
      contains_sensitive_content: ad["contains_sensitive_content"] || false,
      has_user_reported: ad["has_user_reported"] || false,
      report_count: ad["report_count"],
      is_aaa_eligible: ad["is_aaa_eligible"] || false
    }
  end

  defp extract_body_text(snapshot) do
    case snapshot["body"] do
      %{"text" => text} -> text
      _ -> nil
    end
  end
end
