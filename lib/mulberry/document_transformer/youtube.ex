defmodule Mulberry.DocumentTransformer.YouTube do
  @moduledoc """
  Custom DocumentTransformer implementation for YouTube documents.
  Handles YouTube-specific transformation logic for videos, shorts, playlists, and channels.
  """

  @behaviour Mulberry.DocumentTransformer

  alias Mulberry.Text

  @impl true
  def transform(document, transformation, opts \\ [])

  def transform(document, :summary, opts) do
    content = get_content_for_summary(document)
    
    case Text.summarize(content, opts) do
      {:ok, summary} ->
        {:ok, Map.put(document, :summary, summary)}
        
      {:error, error} ->
        {:error, error, document}
    end
  end

  def transform(document, :keywords, _opts) do
    # For now, return empty keywords
    # This could be enhanced with keyword extraction
    {:ok, Map.put(document, :keywords, [])}
  end

  def transform(document, :title, _opts) do
    # YouTube documents already have titles
    {:ok, document}
  end

  def transform(document, transformation, _opts) do
    {:error, {:unsupported_transformation, transformation}, document}
  end

  # Private helper functions for different YouTube document types
  
  defp get_content_for_summary(%{__struct__: struct_name, title: title} = doc) do
    case struct_name do
      Mulberry.Document.YouTubeVideo ->
        get_video_content_for_summary(doc)
      Mulberry.Document.YouTubeShort ->
        get_short_content_for_summary(doc)
      Mulberry.Document.YouTubePlaylist ->
        get_playlist_content_for_summary(doc)
      Mulberry.Document.YouTubeChannel ->
        get_channel_content_for_summary(doc)
      _ ->
        title || ""
    end
  end

  defp get_video_content_for_summary(%{title: title} = video) do
    parts = [
      "Title: #{title}",
      if(video.channel, do: "Channel: #{video.channel.title}", else: nil),
      if(video.view_count_text, do: "Views: #{video.view_count_text}", else: nil),
      if(video.published_time_text, do: "Published: #{video.published_time_text}", else: nil),
      if(video.length_text, do: "Duration: #{video.length_text}", else: nil)
    ]
    
    parts
    |> Enum.filter(& &1)
    |> Enum.join("\n")
  end

  defp get_short_content_for_summary(%{title: title} = short) do
    parts = [
      "Short: #{title}",
      if(short.channel, do: "Channel: #{short.channel.title}", else: nil),
      if(short.view_count_text, do: "Views: #{short.view_count_text}", else: nil),
      if(Map.get(short, :published_time_text), do: "Published: #{short.published_time_text}", else: nil)
    ]
    
    parts
    |> Enum.filter(& &1)
    |> Enum.join("\n")
  end

  defp get_playlist_content_for_summary(%{title: title} = playlist) do
    video_count = if playlist.videos, do: length(playlist.videos), else: 0
    
    parts = [
      "Title: #{title}",
      if(playlist.channel, do: "Channel: #{playlist.channel.title}", else: nil),
      "Videos: #{video_count}",
      if(playlist.updated_text, do: "Updated: #{playlist.updated_text}", else: nil)
    ]
    
    parts
    |> Enum.filter(& &1)
    |> Enum.join("\n")
  end

  defp get_channel_content_for_summary(%{title: title} = channel) do
    parts = [
      "Channel: #{title}",
      if(channel.subscriber_count_text, do: "Subscribers: #{channel.subscriber_count_text}", else: nil),
      if(channel.video_count_text, do: "Videos: #{channel.video_count_text}", else: nil),
      if(channel.description, do: "Description: #{String.slice(channel.description, 0, 200)}", else: nil)
    ]
    
    parts
    |> Enum.filter(& &1)
    |> Enum.join("\n\n")
  end
end