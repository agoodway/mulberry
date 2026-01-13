defmodule MulberryTest do
  use ExUnit.Case
  use Mimic
  doctest Mulberry

  alias Mulberry.Document.{File, WebPage}

  describe "config/1" do
    test "returns configuration value for given key" do
      Application.put_env(:mulberry, :test_key, "test_value")
      assert Mulberry.config(:test_key) == "test_value"
      Application.delete_env(:mulberry, :test_key)
    end

    test "returns nil for non-existent key" do
      assert Mulberry.config(:non_existent_key) == nil
    end

    test "returns nil when app config is nil in test mode" do
      # Clear any existing app config
      Application.delete_env(:mulberry, :brave_api_key)

      # In test mode, should return nil instead of checking env vars
      assert Mulberry.config(:brave_api_key) == nil
    end

    test "prefers app config over environment variable" do
      # Set both app config and env var
      Application.put_env(:mulberry, :brave_api_key, "app_key")

      original_env = System.get_env("BRAVE_API_KEY")
      System.put_env("BRAVE_API_KEY", "env_key")

      assert Mulberry.config(:brave_api_key) == "app_key"

      # Cleanup
      Application.delete_env(:mulberry, :brave_api_key)

      if original_env do
        System.put_env("BRAVE_API_KEY", original_env)
      else
        System.delete_env("BRAVE_API_KEY")
      end
    end

    test "returns nil for common API keys when no app config set in test mode" do
      # Test each mapping
      config_keys = [
        :brave_api_key,
        :scraping_bee_api_key,
        :openai_api_key,
        :anthropic_api_key,
        :google_api_key,
        :mistral_api_key,
        :llm_provider
      ]

      for config_key <- config_keys do
        # Clear app config
        Application.delete_env(:mulberry, config_key)

        # In test mode, should return nil instead of checking env vars
        assert Mulberry.config(config_key) == nil
      end
    end

    test "returns nil for custom keys when no app config set in test mode" do
      Application.delete_env(:mulberry, :custom_key)

      # In test mode, should return nil instead of checking env vars
      assert Mulberry.config(:custom_key) == nil
    end
  end

  describe "search/3" do
    test "searches using the given module and returns documents" do
      module = Mulberry.Search.Brave
      query = "elixir programming"
      limit = 2

      mock_results = [
        %{title: "Result 1", url: "http://example1.com"},
        %{title: "Result 2", url: "http://example2.com"}
      ]

      expect(module, :search, fn ^query, ^limit -> {:ok, mock_results} end)

      expect(module, :to_documents, fn ^mock_results ->
        {:ok,
         [
           %WebPage{url: "http://example1.com", title: "Result 1"},
           %WebPage{url: "http://example2.com", title: "Result 2"}
         ]}
      end)

      {:ok, results} = Mulberry.search(module, query, limit)
      assert length(results) == 2
      assert hd(results).url == "http://example1.com"
    end

    test "uses default limit of 3 when not specified" do
      module = Mulberry.Search.Brave
      query = "test query"

      expect(module, :search, fn ^query, 3 -> {:ok, []} end)
      expect(module, :to_documents, fn [] -> {:ok, []} end)

      {:ok, results} = Mulberry.search(module, query)
      assert results == []
    end
  end

  describe "summarize/2" do
    test "summarizes a web page URL" do
      url = "http://example.com"

      expect(WebPage, :new, fn %{url: ^url} -> %WebPage{url: url} end)

      expect(Mulberry.Document, :load, fn %WebPage{url: ^url}, [] ->
        {:ok, %WebPage{url: url, content: "Test content"}}
      end)

      expect(Mulberry.Document, :generate_summary, fn %WebPage{content: "Test content"} ->
        {:ok, %WebPage{content: "Test content", summary: "Test summary"}}
      end)

      expect(Mulberry.Document, :to_text, fn web_page ->
        assert %WebPage{summary: "Test summary"} = web_page
        "Test summary"
      end)

      result = Mulberry.summarize(url)
      assert result == "Test summary"
    end

    test "summarizes a file path" do
      file_path = "/path/to/file.txt"

      expect(File, :new, fn %{path: ^file_path} -> %File{path: file_path} end)

      expect(Mulberry.Document, :load, fn %File{path: ^file_path}, [] ->
        {:ok, %File{path: file_path, contents: "File content"}}
      end)

      expect(Mulberry.Document, :generate_summary, fn %File{contents: "File content"} ->
        {:ok, %File{contents: "File content", summary: "File summary"}}
      end)

      expect(Mulberry.Document, :to_text, fn file ->
        assert %File{summary: "File summary"} = file
        "File summary"
      end)

      result = Mulberry.summarize(file_path)
      assert result == "File summary"
    end
  end
end
