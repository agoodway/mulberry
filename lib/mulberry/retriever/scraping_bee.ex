defmodule Mulberry.Retriever.ScrapingBee do
  require Logger

  def get(url, _opts \\ []) do
    api_key = Mulberry.config(:scraping_bee_api_key)
    url =
      "https://app.scrapingbee.com/api/v1/?api_key=#{api_key}&url=#{URI.encode_www_form(url)}"

    case Req.get(url) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, %Mulberry.Retriever.Response{status: :ok, content: body}}

      error ->
        Logger.error("#{__MODULE__}.get/2 error=#{inspect(error)}")
        {:error, :failed}
    end
  end
end
