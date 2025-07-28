defmodule Mulberry.Retriever.GoogleAd do
  @moduledoc """
  Retriever implementation for fetching Google Ad details from the ScrapeCreators API.

  This retriever fetches comprehensive Google ad information including variations,
  regional statistics, and impression data.

  ## Configuration

  Requires the `SCRAPECREATORS_API_KEY` environment variable or `:scrapecreators_api_key` in config.

  ## Examples

      # Fetch Google ad details
      {:ok, response} = Mulberry.Retriever.GoogleAd.get("https://adstransparency.google.com/advertiser/AR01614014350098432001/creative/CR10449491775734153217")
      
      # The response contains detailed ad data
      ad_data = response.content
      ad_data["variations"]         # => List of ad variations
      ad_data["regionStats"]        # => Regional impression statistics
      ad_data["overallImpressions"] # => Overall impression range
      
      # Using with Mulberry.Retriever
      {:ok, response} = Mulberry.Retriever.get(
        Mulberry.Retriever.GoogleAd,
        "https://adstransparency.google.com/advertiser/AR01614014350098432001/creative/CR10449491775734153217"
      )
  """

  require Logger
  @behaviour Mulberry.Retriever

  @google_ad_url "https://api.scrapecreators.com/v1/google/ad"

  @impl true
  @spec get(String.t(), Keyword.t()) :: {:ok, Mulberry.Retriever.Response.t()} | {:error, any()}
  def get(url, opts \\ []) do
    api_key = Mulberry.config(:scrapecreators_api_key)

    if api_key do
      fetch_ad_details(url, api_key, opts)
    else
      Logger.error("#{__MODULE__}.get/2 missing SCRAPECREATORS_API_KEY")
      return_error(:missing_api_key, opts)
    end
  end

  defp fetch_ad_details(ad_url, api_key, opts) do
    params = %{url: ad_url}
    headers = %{"x-api-key" => api_key}

    responder = Keyword.get(opts, :responder, &Mulberry.Retriever.Response.default_responder/1)

    case Req.get(@google_ad_url, headers: headers, params: params) do
      {:ok, %Req.Response{status: status, body: body}} when status < 400 ->
        handle_success_response(body, responder)

      {:ok, %Req.Response{status: 429, body: body}} ->
        Logger.warning("#{__MODULE__}.get/2 Rate limited. Body: #{inspect(body)}")

        %Mulberry.Retriever.Response{status: :rate_limited, content: nil}
        |> responder.()

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("#{__MODULE__}.get/2 API error status=#{status} body=#{inspect(body)}")

        %Mulberry.Retriever.Response{status: :failed, content: nil}
        |> responder.()

      {:error, error} ->
        Logger.error("#{__MODULE__}.get/2 request error=#{inspect(error)}")

        %Mulberry.Retriever.Response{status: :failed, content: nil}
        |> responder.()
    end
  end

  defp handle_success_response(body, responder) when is_map(body) do
    case body do
      %{"success" => false, "error" => error} ->
        Logger.error("#{__MODULE__}.get/2 API returned error: #{inspect(error)}")

        %Mulberry.Retriever.Response{status: :failed, content: nil}
        |> responder.()

      %{"success" => true} = ad_data ->
        # Remove the success flag and pass the rest as content
        content = Map.delete(ad_data, "success")

        %Mulberry.Retriever.Response{status: :ok, content: content}
        |> responder.()

      ad_data ->
        # Handle response without explicit success field
        %Mulberry.Retriever.Response{status: :ok, content: ad_data}
        |> responder.()
    end
  end

  defp handle_success_response(body, responder) do
    Logger.error("#{__MODULE__}.get/2 unexpected response format: #{inspect(body)}")

    %Mulberry.Retriever.Response{status: :failed, content: nil}
    |> responder.()
  end

  defp return_error(_reason, opts) do
    responder = Keyword.get(opts, :responder, &Mulberry.Retriever.Response.default_responder/1)

    %Mulberry.Retriever.Response{status: :failed, content: nil}
    |> responder.()
  end
end