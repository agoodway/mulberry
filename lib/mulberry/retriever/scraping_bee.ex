defmodule Mulberry.Retriever.ScrapingBee do
  def get(url, _opts \\ []) do
    api_key = Mulberry.config(:scraping_bee_api_key)
    url =
      "https://app.scrapingbee.com/api/v1/?api_key=#{api_key}&url=#{URI.encode_www_form(url)}"

    case Req.get(url) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, %Mulberry.Retriever.Response{status: :ok, content: body}}

      _ ->
        {:error, :failed}
    end
  end
end
