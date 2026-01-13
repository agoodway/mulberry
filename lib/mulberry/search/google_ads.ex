defmodule Mulberry.Search.GoogleAds do
  @behaviour Mulberry.Search.Behaviour
  @moduledoc """
  Google Ads search using ScrapeCreators API

  Searches for ads by domain or advertiser ID with optional filtering by topic and region.
  Supports pagination through cursor parameter.

  ## Configuration

  Requires the `SCRAPECREATORS_API_KEY` environment variable or `:scrapecreators_api_key` in config.

  ## Examples

      # Search for ads by domain
      {:ok, ads} = Mulberry.search(Mulberry.Search.GoogleAds, "lululemon.com")
      
      # Search with advertiser ID
      {:ok, ads} = Mulberry.search(Mulberry.Search.GoogleAds, nil, 
        advertiser_id: "AR01614014350098432001"
      )
      
      # Search political ads with region
      {:ok, ads} = Mulberry.search(Mulberry.Search.GoogleAds, "example.com",
        topic: "political",
        region: "US"
      )
      
      # Paginate through results
      {:ok, response} = Mulberry.Search.GoogleAds.search("nike.com", 10)
      cursor = response["cursor"]
      {:ok, next_page} = Mulberry.Search.GoogleAds.search("nike.com", 10, cursor: cursor)
      
      # Access ad information
      ad = List.first(ads)
      ad.advertiser_id          # => "AR01614014350098432001"
      ad.creative_id            # => "CR10449491775734153217"
      ad.format                 # => "text"
      ad.ad_url                 # => "https://adstransparency.google.com/..."

  ## API Reference

  https://api.scrapecreators.com/v1/google/company/ads
  """

  require Logger

  @google_ads_url "https://api.scrapecreators.com/v1/google/company/ads"

  @impl true
  @spec search(binary() | nil, pos_integer(), keyword()) ::
          {:ok, map()} | {:error, binary() | atom()}
  def search(query, _count \\ 20, opts \\ []) do
    with :ok <- validate_search_params(query, opts) do
      retriever = Keyword.get(opts, :retriever, Mulberry.Retriever.Req)

      params = build_params(query, opts)

      request_opts = [
        params: params,
        headers: [
          {"x-api-key", Mulberry.config(:scrapecreators_api_key)}
        ]
      ]

      case Mulberry.Retriever.get(retriever, @google_ads_url, request_opts) do
        {:ok, response} -> {:ok, response.content}
        {:error, %{status: :rate_limited}} -> {:error, :rate_limited}
        {:error, _} = error -> error
      end
    end
  end

  @impl true
  @spec to_documents(any()) :: {:ok, [Mulberry.Document.GoogleAd.t()]} | {:error, atom()}
  def to_documents(results) do
    case results do
      %{"ads" => ads} when is_list(ads) ->
        docs = Enum.map(ads, &ad_to_document/1)
        {:ok, docs}

      %{"ads" => []} ->
        {:ok, []}

      %{"error" => error} ->
        Logger.error("#{__MODULE__}.to_documents/1 Google ads search failed: #{inspect(error)}")
        {:error, :api_error}

      response ->
        Logger.error(
          "#{__MODULE__}.to_documents/1 unexpected response format: #{inspect(response)}"
        )

        {:error, :invalid_response_format}
    end
  end

  defp validate_search_params(domain, opts) do
    if is_nil(domain) and is_nil(opts[:advertiser_id]) do
      {:error, :missing_required_parameter}
    else
      :ok
    end
  end

  defp build_params(domain, opts) do
    params = %{}

    # Either domain or advertiser_id is required
    params = if domain, do: Map.put(params, :domain, domain), else: params

    params =
      if opts[:advertiser_id],
        do: Map.put(params, :advertiser_id, opts[:advertiser_id]),
        else: params

    # Optional parameters
    params = if opts[:topic], do: Map.put(params, :topic, opts[:topic]), else: params
    params = if opts[:region], do: Map.put(params, :region, opts[:region]), else: params
    params = if opts[:cursor], do: Map.put(params, :cursor, opts[:cursor]), else: params

    params
  end

  defp ad_to_document(ad) do
    attrs = %{
      advertiser_id: ad["advertiserId"],
      creative_id: ad["creativeId"],
      format: ad["format"],
      ad_url: ad["adUrl"],
      advertiser_name: ad["advertiserName"],
      domain: ad["domain"],
      first_shown: ad["firstShown"],
      last_shown: ad["lastShown"]
    }

    Mulberry.Document.GoogleAd.new(attrs)
  end
end
