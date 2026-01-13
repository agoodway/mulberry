defmodule Mulberry.Document.RedditPostComment do
  @moduledoc """
  Reddit post comments document type for fetching and handling Reddit comments
  from the ScrapeCreators API.

  This module provides functionality to fetch comments for a Reddit post and
  represents them in a structured format with support for nested replies.
  """

  require Logger

  alias __MODULE__
  alias Mulberry.Document.RedditPost

  @type comment :: %{
          # Core fields
          id: String.t(),
          name: String.t(),
          body: String.t(),
          body_html: String.t(),
          permalink: String.t(),
          url: String.t(),

          # Metadata
          author: String.t(),
          author_fullname: String.t() | nil,
          subreddit: String.t(),
          subreddit_id: String.t(),

          # Engagement
          score: integer(),
          ups: integer(),
          downs: integer() | nil,

          # Timestamps
          created_utc: integer(),
          created_at_iso: String.t() | nil,

          # Relations
          parent_id: String.t(),
          link_id: String.t(),
          depth: integer(),
          replies: [comment()] | nil,

          # Flags
          is_submitter: boolean(),
          distinguished: String.t() | nil,
          stickied: boolean(),
          edited: boolean() | integer(),
          archived: boolean(),
          locked: boolean(),
          collapsed: boolean(),
          gilded: integer(),

          # Additional fields
          controversiality: integer() | nil,
          total_awards_received: integer() | nil
        }

  @type t :: %__MODULE__{
          post_url: String.t(),
          post: RedditPost.t() | nil,
          comments: [comment()],
          cursor: String.t() | nil,
          has_more: boolean(),
          meta: keyword()
        }

  defstruct [
    :post_url,
    :post,
    :cursor,
    comments: [],
    has_more: false,
    meta: []
  ]

  @doc """
  Creates a new RedditPostComment document with the given post URL.
  """
  @spec new(String.t() | map()) :: t()
  def new(post_url) when is_binary(post_url) do
    %RedditPostComment{post_url: post_url}
  end

  def new(attrs) when is_map(attrs) do
    struct!(RedditPostComment, attrs)
  end

  defimpl Mulberry.Document do
    alias Mulberry.DocumentTransformer
    alias Mulberry.Retriever
    alias Mulberry.Text

    # Transform function - new unified interface
    @spec transform(RedditPostComment.t(), atom(), keyword()) ::
            {:ok, RedditPostComment.t()} | {:error, any(), RedditPostComment.t()}
    def transform(%RedditPostComment{} = doc, transformation, opts \\ []) do
      transformer = Keyword.get(opts, :transformer, DocumentTransformer.RedditPostComment)
      transformer.transform(doc, transformation, opts)
    end

    @reddit_comments_url "https://api.scrapecreators.com/v1/reddit/post/comments"

    @spec load(RedditPostComment.t(), keyword()) ::
            {:ok, RedditPostComment.t()} | {:error, any(), RedditPostComment.t()}
    def load(%RedditPostComment{post_url: post_url} = doc, opts) when is_binary(post_url) do
      retriever = Keyword.get(opts, :retriever, Retriever.Req)

      params =
        %{url: post_url}
        |> maybe_add_param(:cursor, doc.cursor || Keyword.get(opts, :cursor))
        |> maybe_add_param(:trim, Keyword.get(opts, :trim))

      request_opts = [
        params: params,
        headers: [
          {"x-api-key", Mulberry.config(:scrapecreators_api_key)}
        ]
      ]

      case Retriever.get(retriever, @reddit_comments_url, request_opts) do
        {:ok, response} ->
          parse_comments_response(doc, response.content)

        {:error, error} ->
          {:error, error, doc}
      end
    end

    def load(%RedditPostComment{} = doc, _opts) do
      {:error, :missing_post_url, doc}
    end

    @spec generate_summary(RedditPostComment.t(), keyword()) ::
            {:ok, RedditPostComment.t()} | {:error, any(), RedditPostComment.t()}
    def generate_summary(%RedditPostComment{comments: []} = doc, _opts) do
      {:error, :no_comments, doc}
    end

    def generate_summary(%RedditPostComment{} = doc, opts) do
      # Summarize top-level comments
      top_comments_text =
        doc.comments
        |> Enum.take(5)
        |> Enum.map_join("\n\n", fn comment ->
          "#{comment.author}: #{String.slice(comment.body, 0, 200)}"
        end)

      case Text.summarize(top_comments_text, opts) do
        {:ok, summary} ->
          {:ok, %{doc | meta: Keyword.put(doc.meta, :summary, summary)}}

        {:error, error} ->
          {:error, error, doc}
      end
    end

    @spec generate_keywords(RedditPostComment.t(), keyword()) ::
            {:ok, RedditPostComment.t()} | {:error, any(), RedditPostComment.t()}
    def generate_keywords(%RedditPostComment{} = doc, _opts) do
      # For now, return empty keywords
      {:ok, %{doc | meta: Keyword.put(doc.meta, :keywords, [])}}
    end

    @spec generate_title(RedditPostComment.t(), keyword()) ::
            {:ok, RedditPostComment.t()} | {:error, any(), RedditPostComment.t()}
    def generate_title(%RedditPostComment{post: %RedditPost{title: title}} = doc, _opts)
        when is_binary(title) do
      {:ok, %{doc | meta: Keyword.put(doc.meta, :title, "Comments on: #{title}")}}
    end

    def generate_title(%RedditPostComment{} = doc, _opts) do
      {:ok, %{doc | meta: Keyword.put(doc.meta, :title, "Reddit Comments")}}
    end

    @spec to_text(RedditPostComment.t(), keyword()) :: {:ok, String.t()} | {:error, any()}
    def to_text(%RedditPostComment{comments: comments}, opts) do
      include_nested = Keyword.get(opts, :include_nested, true)
      max_depth = Keyword.get(opts, :max_depth, 3)

      text = comments_to_text(comments, 0, max_depth, include_nested)
      {:ok, text}
    end

    @spec to_tokens(RedditPostComment.t(), keyword()) :: {:ok, [String.t()]} | {:error, any()}
    def to_tokens(%RedditPostComment{} = doc, opts) do
      case to_text(doc, opts) do
        {:ok, text} ->
          case Text.tokens(text) do
            {:ok, tokens} -> {:ok, tokens}
            _ -> {:error, :tokenization_failed}
          end

        _ ->
          {:error, :tokenization_failed}
      end
    end

    @spec to_chunks(RedditPostComment.t(), keyword()) ::
            {:ok, [TextChunker.Chunk.t()]} | {:error, any()}
    def to_chunks(%RedditPostComment{} = doc, opts) do
      case to_text(doc, opts) do
        {:ok, text} ->
          chunks = Text.split(text)
          {:ok, chunks}

        error ->
          error
      end
    end

    @spec to_markdown(RedditPostComment.t(), keyword()) :: {:ok, String.t()} | {:error, any()}
    def to_markdown(%RedditPostComment{comments: comments, post: post}, opts) do
      include_nested = Keyword.get(opts, :include_nested, true)
      max_depth = Keyword.get(opts, :max_depth, 3)

      # Build markdown representation
      post_header =
        if post do
          "# Comments on: #{post.title}\n\n**Subreddit:** #{post.subreddit_prefixed || post.subreddit}\n\n---\n\n"
        else
          "# Reddit Comments\n\n---\n\n"
        end

      comments_markdown = comments_to_markdown(comments, 0, max_depth, include_nested)
      {:ok, post_header <> comments_markdown}
    end

    # Private helper functions

    defp comments_to_markdown(comments, current_depth, max_depth, include_nested) do
      comments
      |> Enum.map_join("\n\n", fn comment ->
        indent = String.duplicate("> ", current_depth)
        header = "#{indent}**#{comment.author}** · #{comment.score} points"
        body = "#{indent}#{comment.body}"

        text = "#{header}\n#{body}"

        if include_nested and current_depth < max_depth and comment.replies != [] do
          nested_text =
            comments_to_markdown(comment.replies, current_depth + 1, max_depth, include_nested)

          "#{text}\n\n#{nested_text}"
        else
          text
        end
      end)
    end

    defp parse_comments_response(doc, %{"success" => false} = error) do
      Logger.error("Reddit comments fetch failed: #{inspect(error)}")
      {:error, :fetch_failed, doc}
    end

    defp parse_comments_response(doc, response) do
      post = parse_post(response["post"])
      comments = parse_comments(response["comments"] || [])

      more_info = response["more"] || %{}
      has_more = more_info["has_more"] || false
      cursor = more_info["cursor"]

      updated_doc = %{doc | post: post, comments: comments, has_more: has_more, cursor: cursor}

      {:ok, updated_doc}
    end

    defp parse_post(nil), do: nil

    defp parse_post(post_data) when is_map(post_data) do
      # Use the same field extraction as in Reddit search
      Mulberry.Document.RedditPost.new(%{
        # Core fields
        id: post_data["id"],
        name: post_data["name"],
        title: post_data["title"],
        selftext: post_data["selftext"],
        url: post_data["url"],
        permalink: post_data["permalink"],

        # Metadata
        subreddit: post_data["subreddit"],
        subreddit_prefixed: post_data["subreddit_name_prefixed"],
        subreddit_subscribers: post_data["subreddit_subscribers"],
        author: post_data["author"],
        author_fullname: post_data["author_fullname"],

        # Engagement metrics
        score: post_data["score"],
        ups: post_data["ups"],
        downs: post_data["downs"],
        upvote_ratio: post_data["upvote_ratio"],
        num_comments: post_data["num_comments"],
        total_awards_received: post_data["total_awards_received"],
        gilded: post_data["gilded"],

        # Timestamps
        created_utc: post_data["created_utc"],
        created_at_iso: post_data["created_at_iso"],

        # Flags
        is_video: post_data["is_video"],
        is_self: post_data["is_self"],
        over_18: post_data["over_18"],
        spoiler: post_data["spoiler"],
        locked: post_data["locked"],
        archived: post_data["archived"],
        stickied: post_data["stickied"],
        pinned: post_data["pinned"],

        # Additional metadata
        link_flair_text: post_data["link_flair_text"],
        domain: post_data["domain"]
      })
    end

    defp parse_comments(comments) when is_list(comments) do
      Enum.map(comments, &parse_comment/1)
    end

    defp parse_comment(comment_data) when is_map(comment_data) do
      replies = parse_comment_replies(comment_data["replies"])

      build_comment_struct(comment_data, replies)
    end

    defp parse_comment_replies(%{"items" => items}) when is_list(items) do
      parse_comments(items)
    end

    defp parse_comment_replies(_), do: []

    defp build_comment_struct(comment_data, replies) do
      %{
        replies: replies
      }
      |> add_core_fields(comment_data)
      |> add_metadata_fields(comment_data)
      |> add_engagement_fields(comment_data)
      |> add_flag_fields(comment_data)
    end

    defp add_core_fields(comment, data) do
      Map.merge(comment, %{
        id: data["id"],
        name: data["name"],
        body: data["body"] || "",
        body_html: data["body_html"] || "",
        permalink: data["permalink"] || "",
        url: data["url"] || "",
        author: data["author"] || "[deleted]",
        author_fullname: data["author_fullname"]
      })
    end

    defp add_metadata_fields(comment, data) do
      Map.merge(comment, %{
        subreddit: data["subreddit"] || "",
        subreddit_id: data["subreddit_id"] || "",
        created_utc: data["created_utc"] || 0,
        created_at_iso: data["created_at_iso"],
        parent_id: data["parent_id"] || "",
        link_id: data["link_id"] || "",
        depth: data["depth"] || 0
      })
    end

    defp add_engagement_fields(comment, data) do
      Map.merge(comment, %{
        score: data["score"] || 0,
        ups: data["ups"] || 0,
        downs: data["downs"] || 0,
        gilded: data["gilded"] || 0,
        controversiality: data["controversiality"],
        total_awards_received: data["total_awards_received"]
      })
    end

    defp add_flag_fields(comment, data) do
      Map.merge(comment, %{
        is_submitter: data["is_submitter"] || false,
        distinguished: data["distinguished"],
        stickied: data["stickied"] || false,
        edited: data["edited"] || false,
        archived: data["archived"] || false,
        locked: data["locked"] || false,
        collapsed: data["collapsed"] || false
      })
    end

    defp comments_to_text(comments, current_depth, max_depth, include_nested) do
      comments
      |> Enum.map_join("\n\n", fn comment ->
        indent = String.duplicate("  ", current_depth)
        text = "#{indent}#{comment.author} (#{comment.score} points):\n#{indent}#{comment.body}"

        if include_nested and current_depth < max_depth and comment.replies != [] do
          nested_text =
            comments_to_text(comment.replies, current_depth + 1, max_depth, include_nested)

          "#{text}\n#{nested_text}"
        else
          text
        end
      end)
    end

    defp maybe_add_param(params, _key, nil), do: params
    defp maybe_add_param(params, key, value), do: Map.put(params, key, value)
  end
end
