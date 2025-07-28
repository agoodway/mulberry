defmodule Mulberry.Document.YouTubeVideo do
  @moduledoc """
  YouTube video document type for handling video results from the ScrapeCreators YouTube API.
  
  This module provides a structured representation of YouTube videos with all their
  metadata and implements the Document protocol for text processing operations.
  """
  
  alias __MODULE__
  
  @type t :: %__MODULE__{
          # Core fields
          type: String.t(),
          id: String.t(),
          url: String.t(),
          title: String.t(),
          thumbnail: String.t() | nil,
          
          # Channel info
          channel: %{
            id: String.t(),
            title: String.t(),
            handle: String.t() | nil,
            thumbnail: String.t() | nil
          } | nil,
          
          # View and engagement metrics
          view_count_text: String.t() | nil,
          view_count_int: integer() | nil,
          
          # Time information
          published_time_text: String.t() | nil,
          published_time: String.t() | nil,
          length_text: String.t() | nil,
          length_seconds: integer() | nil,
          
          # Additional metadata
          badges: [String.t()],
          
          # Generated fields
          summary: String.t() | nil,
          keywords: [String.t()],
          
          # Extra metadata
          meta: keyword()
        }

  defstruct [
    # Core fields
    :type,
    :id,
    :url,
    :title,
    :thumbnail,
    
    # Channel info
    :channel,
    
    # View and engagement metrics
    :view_count_text,
    :view_count_int,
    
    # Time information
    :published_time_text,
    :published_time,
    :length_text,
    :length_seconds,
    
    # Generated fields
    :summary,
    
    # Additional metadata (with defaults)
    badges: [],
    keywords: [],
    meta: []
  ]

  @doc """
  Creates a new YouTubeVideo document struct with the given attributes.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    struct!(YouTubeVideo, attrs)
  end

  defimpl Mulberry.Document do
    alias Mulberry.DocumentTransformer
    alias Mulberry.Text
    
    @spec load(YouTubeVideo.t(), keyword()) :: {:ok, YouTubeVideo.t()} | {:error, any(), YouTubeVideo.t()}
    def load(%YouTubeVideo{} = video, _opts) do
      # YouTube videos come pre-loaded from the search API
      # No additional loading is needed
      {:ok, video}
    end
    
    # Transform function - new unified interface
    @spec transform(YouTubeVideo.t(), atom(), keyword()) :: {:ok, YouTubeVideo.t()} | {:error, any(), YouTubeVideo.t()}
    def transform(%YouTubeVideo{} = video, transformation, opts \\ []) do
      transformer = Keyword.get(opts, :transformer, DocumentTransformer.YouTube)
      transformer.transform(video, transformation, opts)
    end

    # Backward compatibility functions
    @spec generate_summary(YouTubeVideo.t(), keyword()) :: {:ok, YouTubeVideo.t()} | {:error, any(), YouTubeVideo.t()}
    def generate_summary(%YouTubeVideo{} = video, opts \\ []) do
      transform(video, :summary, opts)
    end
    
    @spec generate_keywords(YouTubeVideo.t(), keyword()) :: {:ok, YouTubeVideo.t()} | {:error, any(), YouTubeVideo.t()}
    def generate_keywords(%YouTubeVideo{} = video, opts \\ []) do
      transform(video, :keywords, opts)
    end
    
    @spec generate_title(YouTubeVideo.t(), keyword()) :: {:ok, YouTubeVideo.t()} | {:error, any(), YouTubeVideo.t()}
    def generate_title(%YouTubeVideo{} = video, opts \\ []) do
      transform(video, :title, opts)
    end
    
    @spec to_text(YouTubeVideo.t(), keyword()) :: {:ok, String.t()} | {:error, any()}
    def to_text(%YouTubeVideo{} = video, _opts) do
      text = build_text_representation(video)
      {:ok, text}
    end
    
    @spec to_tokens(YouTubeVideo.t(), keyword()) :: {:ok, [String.t()]} | {:error, any()}
    def to_tokens(%YouTubeVideo{} = video, opts) do
      case to_text(video, opts) do
        {:ok, text} ->
          case Text.tokens(text) do
            {:ok, tokens} -> {:ok, tokens}
            _ -> {:error, :tokenization_failed}
          end
        _ -> 
          {:error, :tokenization_failed}
      end
    end
    
    @spec to_chunks(YouTubeVideo.t(), keyword()) :: {:ok, [TextChunker.Chunk.t()]} | {:error, any()}
    def to_chunks(%YouTubeVideo{} = video, opts) do
      case to_text(video, opts) do
        {:ok, text} ->
          chunks = Text.split(text)
          {:ok, chunks}
        error -> 
          error
      end
    end
    
    # Private helper functions
    
    defp build_text_representation(%YouTubeVideo{} = video) do
      parts = [
        "Title: #{video.title}",
        if(video.channel, do: "Channel: #{video.channel.title}", else: nil),
        if(video.view_count_text, do: "Views: #{video.view_count_text}", else: nil),
        if(video.published_time_text, do: "Published: #{video.published_time_text}", else: nil),
        if(video.length_text, do: "Duration: #{video.length_text}", else: nil),
        if(video.badges != [], do: "Badges: #{Enum.join(video.badges, ", ")}", else: nil),
        "URL: #{video.url}"
      ]
      
      parts
      |> Enum.filter(& &1)
      |> Enum.join("\n")
    end
  end
end