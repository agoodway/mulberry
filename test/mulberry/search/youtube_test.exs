defmodule Mulberry.Search.YouTubeTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Mulberry.Search.YouTube
  alias Mulberry.Retriever
  alias Mulberry.Retriever.Response

  describe "search/3" do
    setup do
      # Set test value
      Application.put_env(:mulberry, :scrapecreators_api_key, "test_api_key")
    end

    test "performs basic search with required parameters" do
      expect(Retriever, :get, fn module, url, opts ->
        assert module == Mulberry.Retriever.Req
        assert url == "https://api.scrapecreators.com/v1/youtube/search"

        # Check params
        assert opts[:params] == %{query: "elixir programming"}

        # Check headers - the headers list should contain the API key tuple
        headers = opts[:headers]
        assert is_list(headers)

        assert Enum.any?(headers, fn
                 {"x-api-key", "test_api_key"} -> true
                 _ -> false
               end),
               "Expected headers to contain {\"x-api-key\", \"test_api_key\"}, but got: #{inspect(headers)}"

        {:ok, %Response{status: :ok, content: %{"videos" => []}}}
      end)

      assert {:ok, %{"videos" => []}} = YouTube.search("elixir programming")
    end

    test "includes optional parameters when provided" do
      expect(Retriever, :get, fn _module, _url, opts ->
        params = opts[:params]
        assert params.query == "test query"
        assert params.uploadDate == "lastMonth"
        assert params.sortBy == "viewCount"
        assert params.filter == "video"
        assert params.continuationToken == "EooDEg..."

        {:ok, %Response{status: :ok, content: %{"videos" => []}}}
      end)

      opts = [
        upload_date: "lastMonth",
        sort_by: "viewCount",
        filter: "video",
        continuation_token: "EooDEg..."
      ]

      assert {:ok, _} = YouTube.search("test query", 20, opts)
    end

    test "handles retriever errors" do
      expect(Retriever, :get, fn _module, _url, _opts ->
        {:error, :connection_failed}
      end)

      assert {:error, :connection_failed} = YouTube.search("test")
    end
  end

  describe "to_documents/1" do
    test "converts videos to YouTubeVideo documents" do
      youtube_response = %{
        "videos" => [
          %{
            "type" => "video",
            "id" => "BzSzwqb-OEE",
            "url" => "https://www.youtube.com/watch?v=BzSzwqb-OEE",
            "title" => "NF - RUNNING (Audio)",
            "thumbnail" => "https://i.ytimg.com/vi/BzSzwqb-OEE/hq720.jpg",
            "channel" => %{
              "id" => "UCoRR6OLuIZ2-5VxtnQIaN2w",
              "title" => "NFrealmusic",
              "handle" => "channel/UCoRR6OLuIZ2-5VxtnQIaN2w",
              "thumbnail" => "https://yt3.ggpht.com/thumbnail.jpg"
            },
            "viewCountText" => "14,860,541 views",
            "viewCountInt" => 14_860_541,
            "publishedTimeText" => "2 years ago",
            "publishedTime" => "2023-05-28T17:08:46.499Z",
            "lengthText" => "4:14",
            "lengthSeconds" => 254,
            "badges" => []
          }
        ],
        "channels" => [],
        "playlists" => [],
        "shorts" => []
      }

      {:ok, [doc]} = YouTube.to_documents(youtube_response)

      assert %Mulberry.Document.YouTubeVideo{} = doc
      assert doc.id == "BzSzwqb-OEE"
      assert doc.url == "https://www.youtube.com/watch?v=BzSzwqb-OEE"
      assert doc.title == "NF - RUNNING (Audio)"
      assert doc.view_count_int == 14_860_541
      assert doc.channel.title == "NFrealmusic"
    end

    test "converts channels to YouTubeChannel documents" do
      youtube_response = %{
        "videos" => [],
        "channels" => [
          %{
            "type" => "channel",
            "id" => "UC123",
            "title" => "Test Channel",
            "handle" => "@testchannel",
            "url" => "https://youtube.com/@testchannel",
            "thumbnail" => "https://yt3.ggpht.com/channel.jpg",
            "subscriberCount" => "100K",
            "videoCount" => "500",
            "description" => "Test channel description"
          }
        ]
      }

      {:ok, [doc]} = YouTube.to_documents(youtube_response)

      assert %Mulberry.Document.YouTubeChannel{} = doc
      assert doc.id == "UC123"
      assert doc.title == "Test Channel"
      assert doc.handle == "@testchannel"
      assert doc.subscriber_count == "100K"
    end

    test "converts playlists to YouTubePlaylist documents" do
      youtube_response = %{
        "videos" => [],
        "playlists" => [
          %{
            "type" => "playlist",
            "id" => "PL123",
            "url" => "https://youtube.com/playlist?list=PL123",
            "title" => "Test Playlist",
            "thumbnail" => "https://i.ytimg.com/vi/playlist.jpg",
            "channel" => %{
              "id" => "UC456",
              "title" => "Playlist Channel",
              "handle" => "@playlistchannel",
              "thumbnail" => "https://yt3.ggpht.com/pchannel.jpg"
            },
            "videoCount" => 25,
            "videoCountText" => "25 videos",
            "firstVideo" => %{
              "id" => "vid123",
              "title" => "First Video",
              "lengthText" => "10:30"
            }
          }
        ]
      }

      {:ok, [doc]} = YouTube.to_documents(youtube_response)

      assert %Mulberry.Document.YouTubePlaylist{} = doc
      assert doc.id == "PL123"
      assert doc.title == "Test Playlist"
      assert doc.video_count == 25
      assert doc.first_video.title == "First Video"
    end

    test "converts shorts to YouTubeShort documents" do
      youtube_response = %{
        "videos" => [],
        "shorts" => [
          %{
            "type" => "short",
            "id" => "uMNvF-lSCHg",
            "url" => "https://www.youtube.com/watch?v=uMNvF-lSCHg",
            "title" => "LONG RUN ROUTINE #run #runvlog",
            "thumbnail" => "https://i.ytimg.com/vi/uMNvF-lSCHg/hq720.jpg",
            "channel" => %{
              "id" => "UCGRdcRxpJWi5Q2oDCrMDUuQ",
              "title" => "Abby and Ryan",
              "handle" => "abbyandryan",
              "thumbnail" => "https://yt3.ggpht.com/channel.jpg"
            },
            "viewCountText" => "462,705 views",
            "viewCountInt" => 462_705,
            "publishedTimeText" => "10 months ago",
            "publishedTime" => "2024-07-28T17:08:46.498Z",
            "lengthText" => "0:44",
            "lengthSeconds" => 44,
            "badges" => []
          }
        ]
      }

      {:ok, [doc]} = YouTube.to_documents(youtube_response)

      assert %Mulberry.Document.YouTubeShort{} = doc
      assert doc.id == "uMNvF-lSCHg"
      assert doc.title == "LONG RUN ROUTINE #run #runvlog"
      assert doc.view_count_int == 462_705
      assert doc.length_seconds == 44
    end

    test "handles mixed content types" do
      youtube_response = %{
        "videos" => [
          %{
            "type" => "video",
            "id" => "vid1",
            "url" => "https://youtube.com/watch?v=vid1",
            "title" => "Video 1",
            "channel" => %{"id" => "ch1", "title" => "Channel 1"}
          }
        ],
        "channels" => [
          %{
            "type" => "channel",
            "id" => "ch1",
            "title" => "Channel 1",
            "subscriberCount" => "1K"
          }
        ],
        "playlists" => [
          %{
            "type" => "playlist",
            "id" => "pl1",
            "url" => "https://youtube.com/playlist?list=pl1",
            "title" => "Playlist 1"
          }
        ],
        "shorts" => [
          %{
            "type" => "short",
            "id" => "short1",
            "url" => "https://youtube.com/shorts/short1",
            "title" => "Short 1"
          }
        ]
      }

      {:ok, docs} = YouTube.to_documents(youtube_response)

      assert length(docs) == 4

      # Verify we have one of each type
      types = docs |> Enum.map(& &1.__struct__) |> Enum.sort()

      assert types == [
               Mulberry.Document.YouTubeChannel,
               Mulberry.Document.YouTubePlaylist,
               Mulberry.Document.YouTubeShort,
               Mulberry.Document.YouTubeVideo
             ]
    end

    test "handles empty results" do
      youtube_response = %{"videos" => []}
      assert {:ok, []} = YouTube.to_documents(youtube_response)
    end

    test "handles missing content type arrays" do
      youtube_response = %{
        "videos" => [
          %{
            "type" => "video",
            "id" => "vid1",
            "url" => "https://youtube.com/watch?v=vid1",
            "title" => "Video 1"
          }
        ]
        # No channels, playlists, or shorts keys
      }

      {:ok, docs} = YouTube.to_documents(youtube_response)
      assert length(docs) == 1
      assert %Mulberry.Document.YouTubeVideo{} = hd(docs)
    end

    test "handles nil channel info" do
      youtube_response = %{
        "videos" => [
          %{
            "type" => "video",
            "id" => "vid1",
            "url" => "https://youtube.com/watch?v=vid1",
            "title" => "Video without channel",
            "channel" => nil
          }
        ]
      }

      {:ok, [doc]} = YouTube.to_documents(youtube_response)
      assert doc.channel == nil
    end

    test "handles unexpected response format" do
      assert {:error, :parse_search_results_failed} = YouTube.to_documents(%{})
      assert {:error, :parse_search_results_failed} = YouTube.to_documents(nil)
      assert {:error, :parse_search_results_failed} = YouTube.to_documents("invalid")
    end
  end
end
