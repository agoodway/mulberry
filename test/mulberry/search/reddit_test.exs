defmodule Mulberry.Search.RedditTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Mulberry.Search.Reddit
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
        assert url == "https://api.scrapecreators.com/v1/reddit/search"
        
        # Check params
        assert opts[:params] == %{query: "elixir programming"}
        
        # Check headers - the headers list should contain the API key tuple
        headers = opts[:headers]
        assert is_list(headers)
        assert Enum.any?(headers, fn 
          {"x-api-key", "test_api_key"} -> true
          _ -> false
        end), "Expected headers to contain {\"x-api-key\", \"test_api_key\"}, but got: #{inspect(headers)}"
        
        {:ok, %Response{status: :ok, content: %{"success" => true, "posts" => []}}}
      end)

      assert {:ok, %{"success" => true, "posts" => []}} = Reddit.search("elixir programming")
    end

    test "includes optional parameters when provided" do
      expect(Retriever, :get, fn _module, _url, opts ->
        params = opts[:params]
        assert params.query == "test query"
        assert params.sort == "top"
        assert params.timeframe == "month"
        assert params.after == "t3_123456"
        assert params.trim == true
        
        {:ok, %Response{status: :ok, content: %{"success" => true, "posts" => []}}}
      end)

      opts = [
        sort: "top",
        timeframe: "month",
        after: "t3_123456",
        trim: true
      ]
      
      assert {:ok, _} = Reddit.search("test query", 20, opts)
    end

    test "handles retriever errors" do
      expect(Retriever, :get, fn _module, _url, _opts ->
        {:error, :connection_failed}
      end)

      assert {:error, :connection_failed} = Reddit.search("test")
    end
  end

  describe "to_documents/1" do
    test "converts successful response with posts to RedditPost documents" do
      reddit_response = %{
        "success" => true,
        "posts" => [
          %{
            "url" => "https://www.reddit.com/r/elixir/comments/test",
            "title" => "Test Post",
            "selftext" => "This is a test post content",
            "subreddit" => "elixir",
            "subreddit_name_prefixed" => "r/elixir",
            "author" => "test_user",
            "author_fullname" => "t2_test123",
            "score" => 42,
            "ups" => 45,
            "downs" => 3,
            "upvote_ratio" => 0.94,
            "num_comments" => 10,
            "created_utc" => 1_234_567_890,
            "created_at_iso" => "2009-02-13T23:31:30.000Z",
            "permalink" => "/r/elixir/comments/test",
            "id" => "test",
            "name" => "t3_test",
            "is_video" => false,
            "is_self" => true,
            "over_18" => false,
            "spoiler" => false,
            "locked" => false,
            "archived" => false,
            "stickied" => false,
            "pinned" => false,
            "gilded" => 0,
            "total_awards_received" => 1,
            "subreddit_subscribers" => 50_000,
            "link_flair_text" => "Discussion",
            "domain" => "self.elixir"
          }
        ]
      }

      {:ok, [doc]} = Reddit.to_documents(reddit_response)
      
      assert %Mulberry.Document.RedditPost{} = doc
      assert doc.url == "https://www.reddit.com/r/elixir/comments/test"
      assert doc.title == "Test Post"
      assert doc.selftext == "This is a test post content"
      
      # Check direct fields instead of metadata
      assert doc.subreddit == "elixir"
      assert doc.author == "test_user"
      assert doc.score == 42
      assert doc.num_comments == 10
      assert doc.upvote_ratio == 0.94
    end

    test "handles empty results" do
      reddit_response = %{"success" => true, "posts" => []}
      assert {:ok, []} = Reddit.to_documents(reddit_response)
    end

    test "preserves full selftext" do
      long_text = String.duplicate("a", 600)
      reddit_response = %{
        "success" => true,
        "posts" => [
          %{
            "url" => "https://reddit.com/r/test/1",
            "title" => "Test",
            "selftext" => long_text,
            "subreddit" => "test",
            "author" => "user",
            "score" => 1,
            "ups" => 1,
            "downs" => 0,
            "num_comments" => 0,
            "created_utc" => 1_234_567_890,
            "permalink" => "/r/test/1",
            "id" => "1",
            "name" => "t3_1",
            "domain" => "self.test"
          }
        ]
      }

      {:ok, [doc]} = Reddit.to_documents(reddit_response)
      assert doc.selftext == long_text
      assert String.length(doc.selftext) == 600
    end

    test "handles nil selftext" do
      reddit_response = %{
        "success" => true,
        "posts" => [
          %{
            "url" => "https://example.com",
            "title" => "External Link",
            "selftext" => nil,
            "subreddit" => "test",
            "author" => "user",
            "score" => 1,
            "ups" => 1,
            "downs" => 0,
            "num_comments" => 0,
            "created_utc" => 1_234_567_890,
            "permalink" => "/r/test/1",
            "id" => "1",
            "name" => "t3_1",
            "domain" => "example.com"
          }
        ]
      }

      {:ok, [doc]} = Reddit.to_documents(reddit_response)
      assert doc.selftext == nil
    end

    test "handles API error response" do
      error_response = %{"success" => false, "error" => "Invalid API key"}
      assert {:error, :search_failed} = Reddit.to_documents(error_response)
    end

    test "handles unexpected response format" do
      assert {:error, :parse_search_results_failed} = Reddit.to_documents(%{})
      assert {:error, :parse_search_results_failed} = Reddit.to_documents(nil)
      assert {:error, :parse_search_results_failed} = Reddit.to_documents("invalid")
    end
  end
end
