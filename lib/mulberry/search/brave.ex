defmodule Mulberry.Search.Brave do
  @behaviour Mulberry.Search.Behaviour
  @moduledoc """
  Web search using Brave

  Docs: https://api.search.brave.com/app/documentation/web-search/get-started
  """

  require Logger

  @brave_search_url "https://api.search.brave.com/res/v1/web/search"

  @impl true
  def search(query, count \\ 20, opts \\ []) do
    retriever = Keyword.get(opts, :retriever, Mulberry.Retriever.Req)
    result_filter = Keyword.get(opts, :result_filter, "web,query")
    include_domains = Keyword.get(opts, :include_domains, [])
    exclude_domains = Keyword.get(opts, :exclude_domains, [])
    
    # Build params
    params = %{
      q: query,
      count: count
    }
    
    # Add result_filter if specified
    params = if result_filter, do: Map.put(params, :result_filter, result_filter), else: params
    
    # Add domain filters if specified
    params = if include_domains != [], do: Map.put(params, :include_domains, Enum.join(include_domains, ",")), else: params
    params = if exclude_domains != [], do: Map.put(params, :exclude_domains, Enum.join(exclude_domains, ",")), else: params

    request_opts = [
      params: params,
      headers: [
        {"Accept", "application/json"},
        {"Accept-Encoding", "gzip"},
        {"X-Subscription-Token", Mulberry.config(:brave_api_key)}
      ]
    ]

    Mulberry.Retriever.get(retriever, @brave_search_url, request_opts)
  end

  @impl true
  def to_documents(results) do
    case results do
      %{"web" => %{"results" => results}} when is_list(results) and length(results) > 0 ->
        docs = Enum.map(results, fn result ->
          result
          |> Map.take(["title", "description", "url"])
          |> Flamel.Map.atomize_keys()
          |> Mulberry.Document.WebPage.new()
        end)
        {:ok, docs}

      %{"web" => %{"results" => []}} ->
        # No results found, which is normal
        {:ok, []}
        
      %{"type" => "search"} ->
        # Search response without web results - this is normal for some queries
        {:ok, []}

      [] ->
        {:ok, []}
        
      list when is_list(list) ->
        # Handle direct list of results
        docs = Enum.map(list, fn result ->
          result
          |> Map.take(["title", "description", "url"])
          |> Flamel.Map.atomize_keys()
          |> Mulberry.Document.WebPage.new()
        end)
        {:ok, docs}

      response ->
        Logger.error("#{__MODULE__}.to_documents/1 unexpected response format: #{inspect(response)}")
        {:error, :parse_search_results_failed}
    end
  end
end
