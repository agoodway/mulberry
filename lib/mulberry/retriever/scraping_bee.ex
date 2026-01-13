defmodule Mulberry.Retriever.ScrapingBee do
  @moduledoc """
  Retriever implementation using the ScrapingBee API service for web scraping.
  Handles complex scraping scenarios including JavaScript rendering and proxy rotation.
  """

  require Logger

  @doc """
  Fetches web content using the ScrapingBee API service.
  """
  @spec get(String.t(), Keyword.t()) :: {:ok, Mulberry.Retriever.Response.t()} | {:error, any()}
  def get(url, opts \\ []) do
    responder =
      Keyword.get(opts, :responder, &Mulberry.Retriever.Response.default_responder/1)

    api_key = Mulberry.config(:scraping_bee_api_key)

    url =
      "https://app.scrapingbee.com/api/v1/?api_key=#{api_key}&url=#{URI.encode_www_form(url)}"

    case Req.get(url) do
      {:ok, %Req.Response{status: status, body: body}} when status < 400 ->
        %Mulberry.Retriever.Response{status: :ok, content: body}

      error ->
        Logger.error("#{__MODULE__}.get/2 error=#{inspect(error)}")
        %Mulberry.Retriever.Response{status: :failed, content: nil}
    end
    |> responder.()
  end
end
