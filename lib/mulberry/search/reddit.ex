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

      # Access Reddit-specific fields
      post = List.first(posts)
      post.subreddit             # => "MachineLearning"
      post.score                 # => 156
      post.num_comments          # => 42
      post.author                # => "reddit_user"
      post.is_self               # => true

  ## API Reference

  https://api.scrapecreators.com/v1/reddit/search
  """

  require Logger

  @reddit_search_url "https://api.scrapecreators.com/v1/reddit/search"

  @impl true
  @spec search(binary(), pos_integer(), keyword()) :: {:ok, map()} | {:error, binary()}
  def search(query, _count \\ 20, opts \\ []) do
    retriever = Keyword.get(opts, :retriever, Mulberry.Retriever.Req)

    # Build parameters - only add 'query' which is required
    params = %{query: query}
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
  @spec to_documents(any()) :: {:ok, [Mulberry.Document.RedditPost.t()]} | {:error, atom()}
  def to_documents(results) do
    case results do
      %{"success" => true, "posts" => posts} when is_list(posts) ->
        docs = Enum.map(posts, &reddit_post_to_document/1)
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

  defp reddit_post_to_document(post) do
    Mulberry.Document.RedditPost.new(%{
      # Core fields
      id: post["id"],
      name: post["name"],
      title: post["title"],
      selftext: post["selftext"],
      url: post["url"],
      permalink: post["permalink"],
      
      # Metadata
      subreddit: post["subreddit"],
      subreddit_prefixed: post["subreddit_name_prefixed"],
      subreddit_subscribers: post["subreddit_subscribers"],
      author: post["author"],
      author_fullname: post["author_fullname"],
      
      # Engagement metrics
      score: post["score"],
      ups: post["ups"],
      downs: post["downs"],
      upvote_ratio: post["upvote_ratio"],
      num_comments: post["num_comments"],
      total_awards_received: post["total_awards_received"],
      gilded: post["gilded"],
      
      # Timestamps
      created_utc: post["created_utc"],
      created_at_iso: post["created_at_iso"],
      
      # Flags
      is_video: post["is_video"],
      is_self: post["is_self"],
      over_18: post["over_18"],
      spoiler: post["spoiler"],
      locked: post["locked"],
      archived: post["archived"],
      stickied: post["stickied"],
      pinned: post["pinned"],
      
      # Additional metadata
      link_flair_text: post["link_flair_text"],
      domain: post["domain"]
    })
  end

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: Map.put(params, key, value)
end