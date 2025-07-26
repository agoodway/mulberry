defmodule Mulberry.Document.YouTubeShort do
  @moduledoc """
  YouTube Short document type for handling short-form video results from the ScrapeCreators YouTube API.
  
  This module provides a structured representation of YouTube Shorts with all their
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
  Creates a new YouTubeShort document struct with the given attributes.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    struct!(YouTubeShort, attrs)
  end

  defimpl Mulberry.Document do
    alias Mulberry.Text
    
    @spec load(YouTubeShort.t(), keyword()) :: {:ok, YouTubeShort.t()} | {:error, any(), YouTubeShort.t()}
    def load(%YouTubeShort{} = short, _opts) do
      # YouTube shorts come pre-loaded from the search API
      # No additional loading is needed
      {:ok, short}
    end
    
    @spec generate_summary(YouTubeShort.t(), keyword()) :: {:ok, YouTubeShort.t()} | {:error, any(), YouTubeShort.t()}
    def generate_summary(%YouTubeShort{} = short, opts) do
      content = get_content_for_summary(short)
      
      case Text.summarize(content, opts) do
        {:ok, summary} ->
          {:ok, %{short | summary: summary}}
          
        {:error, error} ->
          {:error, error, short}
      end
    end
    
    @spec generate_keywords(YouTubeShort.t(), keyword()) :: {:ok, YouTubeShort.t()} | {:error, any(), YouTubeShort.t()}
    def generate_keywords(%YouTubeShort{} = short, _opts) do
      # For now, return empty keywords
      # This could be enhanced with keyword extraction from title
      {:ok, %{short | keywords: []}}
    end
    
    @spec generate_title(YouTubeShort.t(), keyword()) :: {:ok, YouTubeShort.t()} | {:error, any(), YouTubeShort.t()}
    def generate_title(%YouTubeShort{} = short, _opts) do
      # YouTube shorts already have titles
      {:ok, short}
    end
    
    @spec to_text(YouTubeShort.t(), keyword()) :: {:ok, String.t()} | {:error, any()}
    def to_text(%YouTubeShort{} = short, _opts) do
      text = build_text_representation(short)
      {:ok, text}
    end
    
    @spec to_tokens(YouTubeShort.t(), keyword()) :: {:ok, [String.t()]} | {:error, any()}
    def to_tokens(%YouTubeShort{} = short, opts) do
      case to_text(short, opts) do
        {:ok, text} ->
          case Text.tokens(text) do
            {:ok, tokens} -> {:ok, tokens}
            _ -> {:error, :tokenization_failed}
          end
        _ -> 
          {:error, :tokenization_failed}
      end
    end
    
    @spec to_chunks(YouTubeShort.t(), keyword()) :: {:ok, [TextChunker.Chunk.t()]} | {:error, any()}
    def to_chunks(%YouTubeShort{} = short, opts) do
      case to_text(short, opts) do
        {:ok, text} ->
          chunks = Text.split(text)
          {:ok, chunks}
        error -> 
          error
      end
    end
    
    # Private helper functions
    
    defp get_content_for_summary(%YouTubeShort{title: title} = short) do
      parts = [
        "Short: #{title}",
        if(short.channel, do: "Channel: #{short.channel.title}", else: nil),
        if(short.view_count_text, do: "Views: #{short.view_count_text}", else: nil),
        if(short.published_time_text, do: "Published: #{short.published_time_text}", else: nil)
      ]
      
      parts
      |> Enum.filter(& &1)
      |> Enum.join("\n")
    end
    
    defp build_text_representation(%YouTubeShort{} = short) do
      parts = [
        "Short: #{short.title}",
        if(short.channel, do: "Channel: #{short.channel.title}", else: nil),
        if(short.view_count_text, do: "Views: #{short.view_count_text}", else: nil),
        if(short.published_time_text, do: "Published: #{short.published_time_text}", else: nil),
        if(short.length_text, do: "Duration: #{short.length_text}", else: nil),
        if(short.badges != [], do: "Badges: #{Enum.join(short.badges, ", ")}", else: nil),
        "URL: #{short.url}"
      ]
      
      parts
      |> Enum.filter(& &1)
      |> Enum.join("\n")
    end
  end
end