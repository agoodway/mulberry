defmodule Mulberry.Document.RedditPostTest do
  use ExUnit.Case, async: true
  
  alias Mulberry.Document
  alias Mulberry.Document.RedditPost
  
  describe "new/1" do
    test "creates a new RedditPost struct with given attributes" do
      attrs = %{
        id: "abc123",
        title: "Test Post",
        selftext: "This is a test post",
        url: "https://reddit.com/r/test/abc123",
        subreddit: "test",
        author: "testuser",
        score: 100,
        num_comments: 25
      }
      
      post = RedditPost.new(attrs)
      
      assert %RedditPost{} = post
      assert post.id == "abc123"
      assert post.title == "Test Post"
      assert post.selftext == "This is a test post"
      assert post.url == "https://reddit.com/r/test/abc123"
      assert post.subreddit == "test"
      assert post.author == "testuser"
      assert post.score == 100
      assert post.num_comments == 25
    end
  end
  
  describe "Document.load/2" do
    test "returns the post unchanged (pre-loaded from API)" do
      post = RedditPost.new(%{title: "Test", id: "123"})
      
      assert {:ok, ^post} = Document.load(post)
    end
  end
  
  describe "Document.generate_summary/2" do
    test "generates summary from selftext when available" do
      post = RedditPost.new(%{
        title: "Test Title",
        selftext: "This is a long post about Elixir programming. It covers many topics."
      })
      
      # Mock the Text.summarize function
      Mimic.expect(Mulberry.Text, :summarize, fn text, _opts ->
        assert text =~ "Test Title"
        assert text =~ "This is a long post"
        {:ok, "Summary of the post"}
      end)
      
      assert {:ok, updated_post} = Document.generate_summary(post)
      assert updated_post.summary == "Summary of the post"
    end
    
    test "generates summary from title only when selftext is empty" do
      post = RedditPost.new(%{
        title: "Test Title",
        selftext: ""
      })
      
      Mimic.expect(Mulberry.Text, :summarize, fn text, _opts ->
        assert text == "Test Title"
        {:ok, "Summary from title"}
      end)
      
      assert {:ok, updated_post} = Document.generate_summary(post)
      assert updated_post.summary == "Summary from title"
    end
    
    test "handles summarization errors" do
      post = RedditPost.new(%{title: "Test", selftext: "Content"})
      
      Mimic.expect(Mulberry.Text, :summarize, fn _text, _opts ->
        {:error, "API error"}
      end)
      
      assert {:error, "API error", ^post} = Document.generate_summary(post)
    end
  end
  
  describe "Document.generate_keywords/2" do
    test "returns empty keywords for now" do
      post = RedditPost.new(%{title: "Test"})
      
      assert {:ok, updated_post} = Document.generate_keywords(post)
      assert updated_post.keywords == []
    end
  end
  
  describe "Document.generate_title/2" do
    test "returns the post unchanged (already has title)" do
      post = RedditPost.new(%{title: "Existing Title"})
      
      assert {:ok, ^post} = Document.generate_title(post)
    end
  end
  
  describe "Document.to_text/2" do
    test "converts post to text representation with all fields" do
      post = RedditPost.new(%{
        title: "Test Post",
        selftext: "This is the post content",
        subreddit: "elixir",
        subreddit_prefixed: "r/elixir",
        author: "testuser",
        score: 150,
        num_comments: 30,
        link_flair_text: "Discussion"
      })
      
      assert {:ok, text} = Document.to_text(post)
      
      assert text =~ "Title: Test Post"
      assert text =~ "This is the post content"
      assert text =~ "Subreddit: r/elixir"
      assert text =~ "Author: testuser"
      assert text =~ "Score: 150"
      assert text =~ "Comments: 30"
      assert text =~ "Flair: Discussion"
    end
    
    test "converts post without selftext" do
      post = RedditPost.new(%{
        title: "Link Post",
        selftext: nil,
        subreddit: "news",
        author: "newsbot",
        score: 1000,
        num_comments: 200
      })
      
      assert {:ok, text} = Document.to_text(post)
      
      assert text =~ "Title: Link Post"
      refute text =~ "This is the post content"
      assert text =~ "Subreddit: news"
      assert text =~ "Author: newsbot"
      assert text =~ "Score: 1000"
      assert text =~ "Comments: 200"
    end
  end
  
  describe "Document.to_tokens/2" do
    test "tokenizes the post text" do
      post = RedditPost.new(%{
        title: "Test Post",
        selftext: "Content",
        subreddit: "test",
        author: "user",
        score: 10,
        num_comments: 5
      })
      
      Mimic.expect(Mulberry.Text, :tokens, fn text ->
        assert is_binary(text)
        {:ok, ["test", "post", "content"]}
      end)
      
      assert {:ok, tokens} = Document.to_tokens(post)
      assert tokens == ["test", "post", "content"]
    end
    
    test "handles tokenization failure" do
      post = RedditPost.new(%{title: "Test"})
      
      Mimic.expect(Mulberry.Text, :tokens, fn _text ->
        {:error, "tokenization error"}
      end)
      
      assert {:error, :tokenization_failed} = Document.to_tokens(post)
    end
  end
  
  describe "Document.to_chunks/2" do
    test "splits post into chunks" do
      post = RedditPost.new(%{
        title: "Test Post",
        selftext: "Long content that needs to be chunked",
        subreddit: "test",
        author: "user",
        score: 10,
        num_comments: 5
      })
      
      Mimic.expect(Mulberry.Text, :split, fn text ->
        assert is_binary(text)
        [%TextChunker.Chunk{text: "chunk1"}, %TextChunker.Chunk{text: "chunk2"}]
      end)
      
      assert {:ok, chunks} = Document.to_chunks(post)
      assert length(chunks) == 2
    end
  end
end