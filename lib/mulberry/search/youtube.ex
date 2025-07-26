defmodule Mulberry.Search.YouTube do
  @behaviour Mulberry.Search.Behaviour
  @moduledoc """
  YouTube search using ScrapeCreators API
  
  Provides comprehensive YouTube search functionality with support for videos, channels,
  playlists, shorts, and live streams.
  
  ## Configuration
  
  Requires the `SCRAPECREATORS_API_KEY` environment variable or `:scrapecreators_api_key` in config.
  
  ## Examples
  
      # Basic search
      {:ok, results} = Mulberry.search(Mulberry.Search.YouTube, "elixir programming")
      
      # Advanced search with options
      {:ok, response} = Mulberry.Search.YouTube.search("machine learning", 20,
        sort_by: "viewCount",
        upload_date: "lastMonth",
        filter: "video"
      )
      {:ok, documents} = Mulberry.Search.YouTube.to_documents(response)
      
      # Pagination with continuation token
      {:ok, response} = Mulberry.Search.YouTube.search("elixir", 20,
        continuation_token: "EooDEg..."
      )
  
  ## API Reference
  
  https://api.scrapecreators.com/v1/youtube/search
  
  Video explaining the response format: https://www.tella.tv/video/explaining-youtube-search-results-payload-353a
  """
  
  require Logger
  
  @youtube_search_url "https://api.scrapecreators.com/v1/youtube/search"
  
  @impl true
  @spec search(binary(), pos_integer(), keyword()) :: {:ok, map()} | {:error, binary()}
  def search(query, _count \\ 20, opts \\ []) do
    retriever = Keyword.get(opts, :retriever, Mulberry.Retriever.Req)
    
    # Build parameters - only add 'query' which is required
    params = %{query: query}
    |> maybe_add_param(:uploadDate, Keyword.get(opts, :upload_date))
    |> maybe_add_param(:sortBy, Keyword.get(opts, :sort_by))
    |> maybe_add_param(:filter, Keyword.get(opts, :filter))
    |> maybe_add_param(:continuationToken, Keyword.get(opts, :continuation_token))
    
    request_opts = [
      params: params,
      headers: [
        {"x-api-key", Mulberry.config(:scrapecreators_api_key)}
      ]
    ]
    
    case Mulberry.Retriever.get(retriever, @youtube_search_url, request_opts) do
      {:ok, response} -> {:ok, response.content}
      {:error, _} = error -> error
    end
  end
  
  @impl true
  @spec to_documents(any()) :: {:ok, [Mulberry.Document.YouTubeVideo.t() | Mulberry.Document.YouTubeChannel.t() | Mulberry.Document.YouTubePlaylist.t() | Mulberry.Document.YouTubeShort.t()]} | {:error, atom()}
  def to_documents(results) do
    case results do
      %{"videos" => videos} = response when is_list(videos) ->
        # Process all content types
        video_docs = convert_videos(videos)
        channel_docs = convert_channels(Map.get(response, "channels", []))
        playlist_docs = convert_playlists(Map.get(response, "playlists", []))
        short_docs = convert_shorts(Map.get(response, "shorts", []))
        
        # Combine all documents
        all_docs = video_docs ++ channel_docs ++ playlist_docs ++ short_docs
        {:ok, all_docs}
        
      %{"videos" => []} ->
        # No results found
        {:ok, []}
        
      response ->
        Logger.error("#{__MODULE__}.to_documents/1 unexpected response format: #{inspect(response)}")
        {:error, :parse_search_results_failed}
    end
  end
  
  # Private helper functions
  
  defp convert_videos(videos) when is_list(videos) do
    Enum.map(videos, &video_to_document/1)
  end
  
  defp convert_channels(channels) when is_list(channels) do
    Enum.map(channels, &channel_to_document/1)
  end
  
  defp convert_playlists(playlists) when is_list(playlists) do
    Enum.map(playlists, &playlist_to_document/1)
  end
  
  defp convert_shorts(shorts) when is_list(shorts) do
    Enum.map(shorts, &short_to_document/1)
  end
  
  defp video_to_document(video) do
    Mulberry.Document.YouTubeVideo.new(%{
      type: video["type"],
      id: video["id"],
      url: video["url"],
      title: video["title"],
      thumbnail: video["thumbnail"],
      channel: convert_channel_info(video["channel"]),
      view_count_text: video["viewCountText"],
      view_count_int: video["viewCountInt"],
      published_time_text: video["publishedTimeText"],
      published_time: video["publishedTime"],
      length_text: video["lengthText"],
      length_seconds: video["lengthSeconds"],
      badges: video["badges"] || []
    })
  end
  
  defp channel_to_document(channel) do
    Mulberry.Document.YouTubeChannel.new(%{
      type: channel["type"],
      id: channel["id"],
      title: channel["title"],
      handle: channel["handle"],
      url: channel["url"],
      thumbnail: channel["thumbnail"],
      subscriber_count: channel["subscriberCount"],
      video_count: channel["videoCount"],
      description: channel["description"]
    })
  end
  
  defp playlist_to_document(playlist) do
    Mulberry.Document.YouTubePlaylist.new(%{
      type: playlist["type"],
      id: playlist["id"],
      url: playlist["url"],
      title: playlist["title"],
      thumbnail: playlist["thumbnail"],
      channel: convert_channel_info(playlist["channel"]),
      video_count: playlist["videoCount"],
      video_count_text: playlist["videoCountText"],
      first_video: convert_first_video_info(playlist["firstVideo"])
    })
  end
  
  defp short_to_document(short) do
    Mulberry.Document.YouTubeShort.new(%{
      type: short["type"],
      id: short["id"],
      url: short["url"],
      title: short["title"],
      thumbnail: short["thumbnail"],
      channel: convert_channel_info(short["channel"]),
      view_count_text: short["viewCountText"],
      view_count_int: short["viewCountInt"],
      published_time_text: short["publishedTimeText"],
      published_time: short["publishedTime"],
      length_text: short["lengthText"],
      length_seconds: short["lengthSeconds"],
      badges: short["badges"] || []
    })
  end
  
  defp convert_channel_info(nil), do: nil
  defp convert_channel_info(channel) when is_map(channel) do
    %{
      id: channel["id"],
      title: channel["title"],
      handle: channel["handle"],
      thumbnail: channel["thumbnail"]
    }
  end
  
  defp convert_first_video_info(nil), do: nil
  defp convert_first_video_info(video) when is_map(video) do
    %{
      id: video["id"],
      title: video["title"],
      length_text: video["lengthText"]
    }
  end
  
  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: Map.put(params, key, value)
end