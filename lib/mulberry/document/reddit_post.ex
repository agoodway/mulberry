defmodule Mulberry.Document.RedditPost do
  @moduledoc """
  Reddit post document type for handling Reddit posts from the ScrapeCreators API.
  
  This module provides a structured representation of Reddit posts with all their
  metadata and implements the Document protocol for text processing operations.
  """
  
  alias __MODULE__
  
  @type t :: %__MODULE__{
          # Core fields
          id: String.t(),
          name: String.t(),
          title: String.t(),
          selftext: String.t() | nil,
          url: String.t(),
          permalink: String.t(),
          
          # Metadata
          subreddit: String.t(),
          subreddit_prefixed: String.t(),
          subreddit_subscribers: integer() | nil,
          author: String.t(),
          author_fullname: String.t() | nil,
          
          # Engagement metrics
          score: integer(),
          ups: integer(),
          downs: integer(),
          upvote_ratio: float() | nil,
          num_comments: integer(),
          total_awards_received: integer() | nil,
          gilded: integer() | nil,
          
          # Timestamps
          created_utc: integer(),
          created_at_iso: String.t() | nil,
          
          # Flags
          is_video: boolean(),
          is_self: boolean(),
          over_18: boolean(),
          spoiler: boolean(),
          locked: boolean(),
          archived: boolean(),
          stickied: boolean(),
          pinned: boolean() | nil,
          
          # Additional metadata
          link_flair_text: String.t() | nil,
          domain: String.t() | nil,
          
          # Generated fields
          summary: String.t() | nil,
          keywords: [String.t()],
          
          # Extra metadata
          meta: keyword()
        }

  defstruct [
    # Core fields
    :id,
    :name,
    :title,
    :selftext,
    :url,
    :permalink,
    
    # Metadata
    :subreddit,
    :subreddit_prefixed,
    :subreddit_subscribers,
    :author,
    :author_fullname,
    
    # Engagement metrics
    :score,
    :ups,
    :downs,
    :upvote_ratio,
    :num_comments,
    :total_awards_received,
    :gilded,
    
    # Timestamps
    :created_utc,
    :created_at_iso,
    
    # Flags
    :is_video,
    :is_self,
    :over_18,
    :spoiler,
    :locked,
    :archived,
    :stickied,
    :pinned,
    
    # Additional metadata
    :link_flair_text,
    :domain,
    
    # Generated fields
    :summary,
    keywords: [],
    
    # Extra metadata
    meta: []
  ]

  @doc """
  Creates a new RedditPost document struct with the given attributes.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    struct!(RedditPost, attrs)
  end

  defimpl Mulberry.Document do
    alias Mulberry.Text
    
    @spec load(RedditPost.t(), keyword()) :: {:ok, RedditPost.t()} | {:error, any(), RedditPost.t()}
    def load(%RedditPost{} = post, _opts) do
      # Reddit posts come pre-loaded from the search API
      # No additional loading is needed
      {:ok, post}
    end
    
    @spec generate_summary(RedditPost.t(), keyword()) :: {:ok, RedditPost.t()} | {:error, any(), RedditPost.t()}
    def generate_summary(%RedditPost{} = post, opts) do
      content = get_content_for_summary(post)
      
      case Text.summarize(content, opts) do
        {:ok, summary} ->
          {:ok, %{post | summary: summary}}
          
        {:error, error} ->
          {:error, error, post}
      end
    end
    
    @spec generate_keywords(RedditPost.t(), keyword()) :: {:ok, RedditPost.t()} | {:error, any(), RedditPost.t()}
    def generate_keywords(%RedditPost{} = post, _opts) do
      # For now, return empty keywords
      # This could be enhanced with keyword extraction from title/selftext
      {:ok, %{post | keywords: []}}
    end
    
    @spec generate_title(RedditPost.t(), keyword()) :: {:ok, RedditPost.t()} | {:error, any(), RedditPost.t()}
    def generate_title(%RedditPost{} = post, _opts) do
      # Reddit posts already have titles
      {:ok, post}
    end
    
    @spec to_text(RedditPost.t(), keyword()) :: {:ok, String.t()} | {:error, any()}
    def to_text(%RedditPost{} = post, _opts) do
      text = build_text_representation(post)
      {:ok, text}
    end
    
    @spec to_tokens(RedditPost.t(), keyword()) :: {:ok, [String.t()]} | {:error, any()}
    def to_tokens(%RedditPost{} = post, opts) do
      case to_text(post, opts) do
        {:ok, text} ->
          case Text.tokens(text) do
            {:ok, tokens} -> {:ok, tokens}
            _ -> {:error, :tokenization_failed}
          end
        _ -> 
          {:error, :tokenization_failed}
      end
    end
    
    @spec to_chunks(RedditPost.t(), keyword()) :: {:ok, [TextChunker.Chunk.t()]} | {:error, any()}
    def to_chunks(%RedditPost{} = post, opts) do
      case to_text(post, opts) do
        {:ok, text} ->
          chunks = Text.split(text)
          {:ok, chunks}
        error -> 
          error
      end
    end
    
    # Private helper functions
    
    defp get_content_for_summary(%RedditPost{selftext: selftext, title: title}) when is_binary(selftext) and selftext != "" do
      "Title: #{title}\n\n#{selftext}"
    end
    
    defp get_content_for_summary(%RedditPost{title: title}) do
      title
    end
    
    defp build_text_representation(%RedditPost{} = post) do
      parts = [
        "Title: #{post.title}",
        if(post.selftext && post.selftext != "", do: "\n\n#{post.selftext}", else: nil),
        "\n\nSubreddit: #{post.subreddit_prefixed || post.subreddit}",
        "Author: #{post.author}",
        "Score: #{post.score}",
        "Comments: #{post.num_comments}",
        if(post.link_flair_text, do: "Flair: #{post.link_flair_text}", else: nil)
      ]
      
      parts
      |> Enum.filter(& &1)
      |> Enum.join("\n")
    end
  end
end