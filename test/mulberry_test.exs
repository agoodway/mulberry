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

      expect(module, :search, fn ^query, ^limit -> mock_results end)
      expect(module, :to_documents, fn ^mock_results -> 
        [
          %WebPage{url: "http://example1.com", title: "Result 1"},
          %WebPage{url: "http://example2.com", title: "Result 2"}
        ]
      end)

      results = Mulberry.search(module, query, limit)
      assert length(results) == 2
      assert hd(results).url == "http://example1.com"
    end

    test "uses default limit of 3 when not specified" do
      module = Mulberry.Search.Brave
      query = "test query"

      expect(module, :search, fn ^query, 3 -> [] end)
      expect(module, :to_documents, fn [] -> [] end)

      Mulberry.search(module, query)
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
