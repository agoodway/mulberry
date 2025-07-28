defmodule Mulberry.Document.YouTubeChannel do
  @moduledoc """
  YouTube channel document type for handling channel results from the ScrapeCreators YouTube API.
  
  This module provides a structured representation of YouTube channels with all their
  metadata and implements the Document protocol for text processing operations.
  """
  
  alias __MODULE__
  
  @type t :: %__MODULE__{
          # Core fields
          type: String.t(),
          id: String.t(),
          title: String.t(),
          handle: String.t() | nil,
          url: String.t() | nil,
          thumbnail: String.t() | nil,
          
          # Channel metrics
          subscriber_count: String.t() | nil,
          video_count: String.t() | nil,
          
          # Description
          description: String.t() | nil,
          
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
    :title,
    :handle,
    :url,
    :thumbnail,
    
    # Channel metrics
    :subscriber_count,
    :video_count,
    
    # Description
    :description,
    
    # Generated fields
    :summary,
    
    # Additional metadata (with defaults)
    keywords: [],
    meta: []
  ]

  @doc """
  Creates a new YouTubeChannel document struct with the given attributes.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    struct!(YouTubeChannel, attrs)
  end

  defimpl Mulberry.Document do
    alias Mulberry.DocumentTransformer
    alias Mulberry.Text
    
    @spec load(YouTubeChannel.t(), keyword()) :: {:ok, YouTubeChannel.t()} | {:error, any(), YouTubeChannel.t()}
    def load(%YouTubeChannel{} = channel, _opts) do
      # YouTube channels come pre-loaded from the search API
      # No additional loading is needed
      {:ok, channel}
    end
    
    # Transform function - new unified interface
    @spec transform(YouTubeChannel.t(), atom(), keyword()) :: {:ok, YouTubeChannel.t()} | {:error, any(), YouTubeChannel.t()}
    def transform(%YouTubeChannel{} = channel, transformation, opts \\ []) do
      transformer = Keyword.get(opts, :transformer, DocumentTransformer.YouTube)
      transformer.transform(channel, transformation, opts)
    end

    # Backward compatibility functions
    @spec generate_summary(YouTubeChannel.t(), keyword()) :: {:ok, YouTubeChannel.t()} | {:error, any(), YouTubeChannel.t()}
    def generate_summary(%YouTubeChannel{} = channel, opts \\ []) do
      transform(channel, :summary, opts)
    end
    
    @spec generate_keywords(YouTubeChannel.t(), keyword()) :: {:ok, YouTubeChannel.t()} | {:error, any(), YouTubeChannel.t()}
    def generate_keywords(%YouTubeChannel{} = channel, opts \\ []) do
      transform(channel, :keywords, opts)
    end
    
    @spec generate_title(YouTubeChannel.t(), keyword()) :: {:ok, YouTubeChannel.t()} | {:error, any(), YouTubeChannel.t()}
    def generate_title(%YouTubeChannel{} = channel, opts \\ []) do
      transform(channel, :title, opts)
    end
    
    @spec to_text(YouTubeChannel.t(), keyword()) :: {:ok, String.t()} | {:error, any()}
    def to_text(%YouTubeChannel{} = channel, _opts) do
      text = build_text_representation(channel)
      {:ok, text}
    end
    
    @spec to_tokens(YouTubeChannel.t(), keyword()) :: {:ok, [String.t()]} | {:error, any()}
    def to_tokens(%YouTubeChannel{} = channel, opts) do
      case to_text(channel, opts) do
        {:ok, text} ->
          case Text.tokens(text) do
            {:ok, tokens} -> {:ok, tokens}
            _ -> {:error, :tokenization_failed}
          end
        _ -> 
          {:error, :tokenization_failed}
      end
    end
    
    @spec to_chunks(YouTubeChannel.t(), keyword()) :: {:ok, [TextChunker.Chunk.t()]} | {:error, any()}
    def to_chunks(%YouTubeChannel{} = channel, opts) do
      case to_text(channel, opts) do
        {:ok, text} ->
          chunks = Text.split(text)
          {:ok, chunks}
        error -> 
          error
      end
    end
    
    # Private helper functions
    
    defp build_text_representation(%YouTubeChannel{} = channel) do
      parts = [
        "Channel: #{channel.title}",
        if(channel.handle, do: "Handle: #{channel.handle}", else: nil),
        if(channel.description, do: "Description: #{channel.description}", else: nil),
        if(channel.subscriber_count, do: "Subscribers: #{channel.subscriber_count}", else: nil),
        if(channel.video_count, do: "Videos: #{channel.video_count}", else: nil),
        if(channel.url, do: "URL: #{channel.url}", else: nil)
      ]
      
      parts
      |> Enum.filter(& &1)
      |> Enum.join("\n")
    end
  end
end