defmodule Mulberry.Search.Google do
  @behaviour Mulberry.Search.Behaviour
  @moduledoc """
  Google search using ScrapeCreators API

  Provides search functionality for Google with support for regional search results.

  ## Configuration

  Requires the `SCRAPECREATORS_API_KEY` environment variable or `:scrapecreators_api_key` in config.

  ## Examples

      # Basic search
      {:ok, pages} = Mulberry.search(Mulberry.Search.Google, "elixir programming")

      # Search with regional results
      {:ok, response} = Mulberry.Search.Google.search("machine learning", 20,
        region: "UK"
      )
      {:ok, pages} = Mulberry.Search.Google.to_documents(response)

      # Access page fields
      page = List.first(pages)
      page.url              # => "https://example.com"
      page.title            # => "Machine Learning Guide"
      page.description      # => "A comprehensive guide to..."

  ## API Reference

  https://api.scrapecreators.com/v1/google/search
  """

  require Logger

  @google_search_url "https://api.scrapecreators.com/v1/google/search"

  @impl true
  @spec search(binary(), pos_integer(), keyword()) :: {:ok, map()} | {:error, binary()}
  def search(query, _count \\ 20, opts \\ []) do
    retriever = Keyword.get(opts, :retriever, Mulberry.Retriever.Req)
    region = Keyword.get(opts, :region)

    # Build parameters - only add 'query' which is required
    params = %{query: query}
    params = if region, do: Map.put(params, :region, region), else: params

    request_opts = [
      params: params,
      headers: [
        {"x-api-key", Mulberry.config(:scrapecreators_api_key)}
      ]
    ]

    case Mulberry.Retriever.get(retriever, @google_search_url, request_opts) do
      {:ok, response} -> {:ok, response.content}
      {:error, _} = error -> error
    end
  end

  @impl true
  @spec to_documents(any()) :: {:ok, [Mulberry.Document.WebPage.t()]} | {:error, atom()}
  def to_documents(results) do
    case results do
      %{"success" => true, "results" => results} when is_list(results) ->
        docs = Enum.map(results, &google_result_to_document/1)
        {:ok, docs}

      %{"success" => true, "results" => []} ->
        {:ok, []}

      %{"success" => false} = error ->
        Logger.error("#{__MODULE__}.to_documents/1 Google search failed: #{inspect(error)}")
        {:error, :search_failed}

      response ->
        Logger.error(
          "#{__MODULE__}.to_documents/1 unexpected response format: #{inspect(response)}"
        )

        {:error, :parse_search_results_failed}
    end
  end

  defp google_result_to_document(result) do
    Mulberry.Document.WebPage.new(%{
      url: result["url"],
      title: result["title"],
      description: result["description"]
    })
  end
end
