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
    
    test "falls back to environment variable when app config is nil" do
      # Clear any existing app config
      Application.delete_env(:mulberry, :brave_api_key)
      
      # Set env var
      original_env = System.get_env("BRAVE_API_KEY")
      System.put_env("BRAVE_API_KEY", "env_api_key")
      
      assert Mulberry.config(:brave_api_key) == "env_api_key"
      
      # Restore original env
      if original_env do
        System.put_env("BRAVE_API_KEY", original_env)
      else
        System.delete_env("BRAVE_API_KEY")
      end
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
    
    test "maps common API keys to correct env vars" do
      # Test each mapping
      mappings = [
        {:brave_api_key, "BRAVE_API_KEY"},
        {:scraping_bee_api_key, "SCRAPING_BEE_API_KEY"},
        {:openai_api_key, "OPENAI_API_KEY"},
        {:anthropic_api_key, "ANTHROPIC_API_KEY"},
        {:google_api_key, "GOOGLE_API_KEY"},
        {:mistral_api_key, "MISTRAL_API_KEY"},
        {:llm_provider, "MULBERRY_LLM_PROVIDER"}
      ]
      
      for {config_key, env_key} <- mappings do
        # Clear app config
        Application.delete_env(:mulberry, config_key)
        
        # Save original env
        original = System.get_env(env_key)
        
        # Set test value
        test_value = "test_#{config_key}"
        System.put_env(env_key, test_value)
        
        # Verify mapping
        assert Mulberry.config(config_key) == test_value
        
        # Restore
        if original do
          System.put_env(env_key, original)
        else
          System.delete_env(env_key)
        end
      end
    end
    
    test "prefixes other keys with MULBERRY_ in env lookup" do
      Application.delete_env(:mulberry, :custom_key)
      
      original = System.get_env("MULBERRY_CUSTOM_KEY")
      System.put_env("MULBERRY_CUSTOM_KEY", "custom_value")
      
      assert Mulberry.config(:custom_key) == "custom_value"
      
      if original do
        System.put_env("MULBERRY_CUSTOM_KEY", original)
      else
        System.delete_env("MULBERRY_CUSTOM_KEY")
      end
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
