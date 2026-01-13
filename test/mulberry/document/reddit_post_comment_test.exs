defmodule Mulberry.Document.RedditPostCommentTest do
  use ExUnit.Case, async: true

  alias Mulberry.Document
  alias Mulberry.Document.{RedditPost, RedditPostComment}
  alias Mulberry.Retriever.Response

  describe "new/1" do
    test "creates from URL string" do
      url = "https://reddit.com/r/test/comments/abc123"
      doc = RedditPostComment.new(url)

      assert %RedditPostComment{} = doc
      assert doc.post_url == url
      assert doc.comments == []
      assert doc.has_more == false
    end

    test "creates from attributes map" do
      attrs = %{
        post_url: "https://reddit.com/r/test/comments/abc123",
        cursor: "next_page",
        has_more: true
      }

      doc = RedditPostComment.new(attrs)

      assert %RedditPostComment{} = doc
      assert doc.post_url == attrs.post_url
      assert doc.cursor == "next_page"
      assert doc.has_more == true
    end
  end

  describe "Document.load/2" do
    test "loads comments from API successfully" do
      doc = RedditPostComment.new("https://reddit.com/r/test/comments/abc123")

      response_data = %{
        "success" => true,
        "post" => %{
          "id" => "abc123",
          "name" => "t3_abc123",
          "title" => "Test Post",
          "selftext" => "Post content",
          "url" => "https://reddit.com/r/test/comments/abc123",
          "permalink" => "/r/test/comments/abc123",
          "subreddit" => "test",
          "subreddit_name_prefixed" => "r/test",
          "author" => "testuser",
          "author_fullname" => "t2_testuser",
          "score" => 100,
          "ups" => 100,
          "downs" => 0,
          "upvote_ratio" => 1.0,
          "num_comments" => 2,
          "created_utc" => 1_234_567_890,
          "is_video" => false,
          "is_self" => true,
          "over_18" => false,
          "spoiler" => false,
          "locked" => false,
          "archived" => false,
          "stickied" => false
        },
        "comments" => [
          %{
            "id" => "comment1",
            "body" => "First comment",
            "author" => "user1",
            "score" => 50,
            "depth" => 0,
            "replies" => %{
              "items" => [
                %{
                  "id" => "reply1",
                  "body" => "Reply to first",
                  "author" => "user2",
                  "score" => 10,
                  "depth" => 1,
                  "replies" => %{"items" => []}
                }
              ]
            }
          },
          %{
            "id" => "comment2",
            "body" => "Second comment",
            "author" => "user3",
            "score" => 30,
            "depth" => 0,
            "replies" => %{"items" => []}
          }
        ],
        "more" => %{
          "has_more" => true,
          "cursor" => "next_cursor"
        }
      }

      Mimic.expect(Mulberry.Retriever, :get, fn retriever, url, opts ->
        assert retriever == Mulberry.Retriever.Req
        assert url == "https://api.scrapecreators.com/v1/reddit/post/comments"
        assert opts[:params][:url] == doc.post_url
        assert [{header_name, _api_key}] = opts[:headers]
        assert header_name == "x-api-key"

        {:ok, %Response{status: :ok, content: response_data}}
      end)

      assert {:ok, loaded_doc} = Document.load(doc)

      # Check post was parsed
      assert %RedditPost{} = loaded_doc.post
      assert loaded_doc.post.id == "abc123"
      assert loaded_doc.post.title == "Test Post"

      # Check comments were parsed
      assert length(loaded_doc.comments) == 2

      [comment1, comment2] = loaded_doc.comments
      assert comment1.id == "comment1"
      assert comment1.body == "First comment"
      assert comment1.author == "user1"
      assert comment1.score == 50
      assert length(comment1.replies) == 1

      [reply1] = comment1.replies
      assert reply1.id == "reply1"
      assert reply1.body == "Reply to first"
      assert reply1.depth == 1

      assert comment2.id == "comment2"
      assert comment2.body == "Second comment"
      assert comment2.replies == []

      # Check pagination info
      assert loaded_doc.has_more == true
      assert loaded_doc.cursor == "next_cursor"
    end

    test "handles API errors" do
      doc = RedditPostComment.new("https://reddit.com/r/test/comments/abc123")

      Mimic.expect(Mulberry.Retriever, :get, fn _retriever, _url, _opts ->
        {:error, "Network error"}
      end)

      assert {:error, "Network error", ^doc} = Document.load(doc)
    end

    test "handles API failure response" do
      doc = RedditPostComment.new("https://reddit.com/r/test/comments/abc123")

      Mimic.expect(Mulberry.Retriever, :get, fn _retriever, _url, _opts ->
        {:ok, %Response{status: :ok, content: %{"success" => false, "error" => "Invalid URL"}}}
      end)

      assert {:error, :fetch_failed, ^doc} = Document.load(doc)
    end

    test "requires post_url to be set" do
      doc = %RedditPostComment{}

      assert {:error, :missing_post_url, ^doc} = Document.load(doc)
    end

    test "supports cursor parameter" do
      doc =
        RedditPostComment.new(%{
          post_url: "https://reddit.com/r/test/comments/abc123",
          cursor: "existing_cursor"
        })

      Mimic.expect(Mulberry.Retriever, :get, fn _retriever, _url, opts ->
        assert opts[:params][:cursor] == "existing_cursor"
        {:ok, %Response{status: :ok, content: %{"comments" => [], "more" => %{}}}}
      end)

      assert {:ok, _} = Document.load(doc)
    end

    test "supports trim parameter" do
      doc = RedditPostComment.new("https://reddit.com/r/test/comments/abc123")

      Mimic.expect(Mulberry.Retriever, :get, fn _retriever, _url, opts ->
        assert opts[:params][:trim] == true
        {:ok, %Response{status: :ok, content: %{"comments" => [], "more" => %{}}}}
      end)

      assert {:ok, _} = Document.load(doc, trim: true)
    end
  end

  describe "Document.generate_summary/2" do
    test "generates summary from top comments" do
      doc = %RedditPostComment{
        comments: [
          %{author: "user1", body: "This is a great post about Elixir!", score: 100},
          %{author: "user2", body: "I agree, functional programming is amazing", score: 80},
          %{author: "user3", body: "Has anyone tried this with Phoenix?", score: 60}
        ]
      }

      Mimic.expect(Mulberry.Text, :summarize, fn text, _opts ->
        assert text =~ "user1: This is a great post"
        assert text =~ "user2: I agree"
        assert text =~ "user3: Has anyone"
        {:ok, "Summary of comments"}
      end)

      assert {:ok, updated_doc} = Document.generate_summary(doc)
      assert Keyword.get(updated_doc.meta, :summary) == "Summary of comments"
    end

    test "returns error when no comments" do
      doc = %RedditPostComment{comments: []}

      assert {:error, :no_comments, ^doc} = Document.generate_summary(doc)
    end
  end

  describe "Document.generate_title/2" do
    test "generates title from post title" do
      post = RedditPost.new(%{title: "Original Post Title"})
      doc = %RedditPostComment{post: post}

      assert {:ok, updated_doc} = Document.generate_title(doc)
      assert Keyword.get(updated_doc.meta, :title) == "Comments on: Original Post Title"
    end

    test "generates generic title when no post" do
      doc = %RedditPostComment{}

      assert {:ok, updated_doc} = Document.generate_title(doc)
      assert Keyword.get(updated_doc.meta, :title) == "Reddit Comments"
    end
  end

  describe "Document.to_text/2" do
    test "converts comments to text with nesting" do
      doc = %RedditPostComment{
        comments: [
          %{
            author: "user1",
            body: "Top level comment",
            score: 50,
            replies: [
              %{
                author: "user2",
                body: "Nested reply",
                score: 10,
                replies: []
              }
            ]
          },
          %{
            author: "user3",
            body: "Another top level",
            score: 30,
            replies: []
          }
        ]
      }

      assert {:ok, text} = Document.to_text(doc)

      assert text =~ "user1 (50 points):"
      assert text =~ "Top level comment"
      assert text =~ "  user2 (10 points):"
      assert text =~ "  Nested reply"
      assert text =~ "user3 (30 points):"
      assert text =~ "Another top level"
    end

    test "respects max_depth option" do
      doc = %RedditPostComment{
        comments: [
          %{
            author: "user1",
            body: "Level 0",
            score: 50,
            replies: [
              %{
                author: "user2",
                body: "Level 1",
                score: 10,
                replies: [
                  %{
                    author: "user3",
                    body: "Level 2 - should not appear",
                    score: 5,
                    replies: []
                  }
                ]
              }
            ]
          }
        ]
      }

      assert {:ok, text} = Document.to_text(doc, max_depth: 1)

      assert text =~ "Level 0"
      assert text =~ "Level 1"
      refute text =~ "Level 2"
    end

    test "can exclude nested comments" do
      doc = %RedditPostComment{
        comments: [
          %{
            author: "user1",
            body: "Top level only",
            score: 50,
            replies: [
              %{
                author: "user2",
                body: "Should not appear",
                score: 10,
                replies: []
              }
            ]
          }
        ]
      }

      assert {:ok, text} = Document.to_text(doc, include_nested: false)

      assert text =~ "Top level only"
      refute text =~ "Should not appear"
    end
  end

  describe "Document.to_tokens/2" do
    test "tokenizes comments text" do
      doc = %RedditPostComment{
        comments: [
          %{author: "user1", body: "Test comment", score: 10, replies: []}
        ]
      }

      Mimic.expect(Mulberry.Text, :tokens, fn text ->
        assert text =~ "Test comment"
        {:ok, ["test", "comment"]}
      end)

      assert {:ok, tokens} = Document.to_tokens(doc)
      assert tokens == ["test", "comment"]
    end
  end

  describe "Document.to_chunks/2" do
    test "splits comments into chunks" do
      doc = %RedditPostComment{
        comments: [
          %{author: "user1", body: "Long comment text", score: 10, replies: []},
          %{author: "user2", body: "Another comment", score: 5, replies: []}
        ]
      }

      Mimic.expect(Mulberry.Text, :split, fn text ->
        assert is_binary(text)
        [%TextChunker.Chunk{text: "chunk1"}, %TextChunker.Chunk{text: "chunk2"}]
      end)

      assert {:ok, chunks} = Document.to_chunks(doc)
      assert length(chunks) == 2
    end
  end
end
