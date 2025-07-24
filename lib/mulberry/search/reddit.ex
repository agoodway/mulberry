defmodule Mulberry.Search.Reddit do
  @behaviour Mulberry.Search.Behaviour
  @moduledoc """
  Reddit search using ScrapeCreators API

  Provides search functionality for Reddit posts with comprehensive metadata extraction.

  ## Configuration

  Requires the `SCRAPECREATORS_API_KEY` environment variable or `:scrapecreators_api_key` in config.

  ## Examples

      # Basic search
      {:ok, posts} = Mulberry.search(Mulberry.Search.Reddit, "elixir programming")

      # Advanced search with options
      {:ok, response} = Mulberry.Search.Reddit.search("machine learning", 50,
        sort: "top",
        timeframe: "month",
        trim: true
      )
      {:ok, posts} = Mulberry.Search.Reddit.to_documents(response)

      # Access Reddit-specific metadata
      post = List.first(posts)
      post.type                  # => "SocialMediaPosting"
      post.network               # => "Reddit"
      post.meta[:subreddit]      # => "MachineLearning"
      post.meta[:score]          # => 156
      post.meta[:num_comments]   # => 42

  ## API Reference

  https://api.scrapecreators.com/v1/reddit/search
  """

  require Logger

  @reddit_search_url "https://api.scrapecreators.com/v1/reddit/search"

  @impl true
  @spec search(binary(), pos_integer(), keyword()) :: {:ok, map()} | {:error, binary()}
  def search(query, _count \\ 20, opts \\ []) do
    retriever = Keyword.get(opts, :retriever, Mulberry.Retriever.Req)

    # Build parameters - only add 'q' which is required
    params = %{q: query}
    |> maybe_add_param(:sort, Keyword.get(opts, :sort))
    |> maybe_add_param(:timeframe, Keyword.get(opts, :timeframe))
    |> maybe_add_param(:after, Keyword.get(opts, :after))
    |> maybe_add_param(:trim, Keyword.get(opts, :trim))

    request_opts = [
      params: params,
      headers: [
        {"x-api-key", Mulberry.config(:scrapecreators_api_key)}
      ]
    ]

    case Mulberry.Retriever.get(retriever, @reddit_search_url, request_opts) do
      {:ok, response} -> {:ok, response.content}
      {:error, _} = error -> error
    end
  end

  @impl true
  @spec to_documents(any()) :: {:ok, [Mulberry.Document.WebPage.t()]} | {:error, atom()}
  def to_documents(results) do
    case results do
      %{"success" => true, "posts" => posts} when is_list(posts) ->
        docs = Enum.map(posts, &reddit_post_to_webpage/1)
        {:ok, docs}

      %{"success" => true, "posts" => []} ->
        {:ok, []}

      %{"success" => false} = error ->
        Logger.error("#{__MODULE__}.to_documents/1 Reddit search failed: #{inspect(error)}")
        {:error, :search_failed}

      response ->
        Logger.error("#{__MODULE__}.to_documents/1 unexpected response format: #{inspect(response)}")
        {:error, :parse_search_results_failed}
    end
  end

  defp reddit_post_to_webpage(post) do
    # Extract comprehensive metadata
    meta = [
      subreddit: post["subreddit"],
      subreddit_prefixed: post["subreddit_name_prefixed"],
      author: post["author"],
      author_fullname: post["author_fullname"],
      score: post["score"],
      ups: post["ups"],
      downs: post["downs"],
      upvote_ratio: post["upvote_ratio"],
      num_comments: post["num_comments"],
      created_utc: post["created_utc"],
      created_at_iso: post["created_at_iso"],
      permalink: post["permalink"],
      id: post["id"],
      name: post["name"],
      is_video: post["is_video"],
      is_self: post["is_self"],
      over_18: post["over_18"],
      spoiler: post["spoiler"],
      locked: post["locked"],
      archived: post["archived"],
      stickied: post["stickied"],
      pinned: post["pinned"],
      gilded: post["gilded"],
      total_awards_received: post["total_awards_received"],
      subreddit_subscribers: post["subreddit_subscribers"],
      link_flair_text: post["link_flair_text"],
      domain: post["domain"]
    ]

    %{
      url: post["url"],
      title: post["title"],
      description: truncate_text(post["selftext"] || "", 500),
      type: "SocialMediaPosting",
      network: "Reddit",
      meta: meta
    }
    |> Mulberry.Document.WebPage.new()
  end

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: Map.put(params, key, value)

  defp truncate_text(text, max_length) when byte_size(text) > max_length do
    String.slice(text, 0, max_length) <> "..."
  end
  defp truncate_text(text, _), do: text
end