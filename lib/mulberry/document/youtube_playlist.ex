defmodule Mulberry.Document.YouTubePlaylist do
  @moduledoc """
  YouTube playlist document type for handling playlist results from the ScrapeCreators YouTube API.

  This module provides a structured representation of YouTube playlists with all their
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
          channel:
            %{
              id: String.t(),
              title: String.t(),
              handle: String.t() | nil,
              thumbnail: String.t() | nil
            }
            | nil,

          # Playlist metrics
          video_count: integer() | nil,
          video_count_text: String.t() | nil,

          # First video info
          first_video:
            %{
              id: String.t(),
              title: String.t(),
              length_text: String.t() | nil
            }
            | nil,

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

    # Playlist metrics
    :video_count,
    :video_count_text,

    # First video info
    :first_video,

    # Generated fields
    :summary,

    # Additional metadata (with defaults)
    keywords: [],
    meta: []
  ]

  @doc """
  Creates a new YouTubePlaylist document struct with the given attributes.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    struct!(YouTubePlaylist, attrs)
  end

  defimpl Mulberry.Document do
    alias Mulberry.DocumentTransformer
    alias Mulberry.Text

    # Transform function - new unified interface
    @spec transform(YouTubePlaylist.t(), atom(), keyword()) ::
            {:ok, YouTubePlaylist.t()} | {:error, any(), YouTubePlaylist.t()}
    def transform(%YouTubePlaylist{} = playlist, transformation, opts \\ []) do
      transformer = Keyword.get(opts, :transformer, DocumentTransformer.YouTube)
      transformer.transform(playlist, transformation, opts)
    end

    @spec load(YouTubePlaylist.t(), keyword()) ::
            {:ok, YouTubePlaylist.t()} | {:error, any(), YouTubePlaylist.t()}
    def load(%YouTubePlaylist{} = playlist, _opts) do
      # YouTube playlists come pre-loaded from the search API
      # No additional loading is needed
      {:ok, playlist}
    end

    @spec generate_summary(YouTubePlaylist.t(), keyword()) ::
            {:ok, YouTubePlaylist.t()} | {:error, any(), YouTubePlaylist.t()}
    def generate_summary(%YouTubePlaylist{} = playlist, opts) do
      content = get_content_for_summary(playlist)

      case Text.summarize(content, opts) do
        {:ok, summary} ->
          {:ok, %{playlist | summary: summary}}

        {:error, error} ->
          {:error, error, playlist}
      end
    end

    @spec generate_keywords(YouTubePlaylist.t(), keyword()) ::
            {:ok, YouTubePlaylist.t()} | {:error, any(), YouTubePlaylist.t()}
    def generate_keywords(%YouTubePlaylist{} = playlist, _opts) do
      # For now, return empty keywords
      # This could be enhanced with keyword extraction from title
      {:ok, %{playlist | keywords: []}}
    end

    @spec generate_title(YouTubePlaylist.t(), keyword()) ::
            {:ok, YouTubePlaylist.t()} | {:error, any(), YouTubePlaylist.t()}
    def generate_title(%YouTubePlaylist{} = playlist, _opts) do
      # YouTube playlists already have titles
      {:ok, playlist}
    end

    @spec to_text(YouTubePlaylist.t(), keyword()) :: {:ok, String.t()} | {:error, any()}
    def to_text(%YouTubePlaylist{} = playlist, _opts) do
      text = build_text_representation(playlist)
      {:ok, text}
    end

    @spec to_tokens(YouTubePlaylist.t(), keyword()) :: {:ok, [String.t()]} | {:error, any()}
    def to_tokens(%YouTubePlaylist{} = playlist, opts) do
      case to_text(playlist, opts) do
        {:ok, text} ->
          case Text.tokens(text) do
            {:ok, tokens} -> {:ok, tokens}
            _ -> {:error, :tokenization_failed}
          end

        _ ->
          {:error, :tokenization_failed}
      end
    end

    @spec to_chunks(YouTubePlaylist.t(), keyword()) ::
            {:ok, [TextChunker.Chunk.t()]} | {:error, any()}
    def to_chunks(%YouTubePlaylist{} = playlist, opts) do
      case to_text(playlist, opts) do
        {:ok, text} ->
          chunks = Text.split(text)
          {:ok, chunks}

        error ->
          error
      end
    end

    @spec to_markdown(YouTubePlaylist.t(), keyword()) :: {:ok, String.t()} | {:error, any()}
    def to_markdown(%YouTubePlaylist{} = playlist, _opts) do
      # YouTube playlists are structured data, return as markdown-formatted text
      text = build_markdown_representation(playlist)
      {:ok, text}
    end

    # Private helper functions

    defp build_markdown_representation(%YouTubePlaylist{} = playlist) do
      parts = [
        "# #{playlist.title}",
        "",
        if(playlist.channel, do: "**Channel:** #{playlist.channel.title}", else: nil),
        if(playlist.video_count_text, do: "**Videos:** #{playlist.video_count_text}", else: nil),
        if(playlist.first_video, do: "**First Video:** #{playlist.first_video.title}", else: nil),
        "",
        "**URL:** #{playlist.url}"
      ]

      parts
      |> Enum.filter(& &1)
      |> Enum.join("\n")
    end

    defp get_content_for_summary(%YouTubePlaylist{} = playlist) do
      parts = [
        "Playlist: #{playlist.title}",
        if(playlist.channel, do: "Channel: #{playlist.channel.title}", else: nil),
        if(playlist.video_count_text, do: "Videos: #{playlist.video_count_text}", else: nil),
        if(playlist.first_video, do: "First video: #{playlist.first_video.title}", else: nil)
      ]

      parts
      |> Enum.filter(& &1)
      |> Enum.join("\n")
    end

    defp build_text_representation(%YouTubePlaylist{} = playlist) do
      parts = [
        "Playlist: #{playlist.title}",
        if(playlist.channel, do: "Channel: #{playlist.channel.title}", else: nil),
        if(playlist.video_count_text, do: "Videos: #{playlist.video_count_text}", else: nil),
        if(playlist.first_video, do: "First video: #{playlist.first_video.title}", else: nil),
        "URL: #{playlist.url}"
      ]

      parts
      |> Enum.filter(& &1)
      |> Enum.join("\n")
    end
  end
end
