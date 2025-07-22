defmodule Mulberry.RetrieverTest do
  use ExUnit.Case, async: true
  use Mimic
  import ExUnit.CaptureLog
  doctest Mulberry.Retriever

  alias Mulberry.Retriever
  alias Mulberry.Retriever.{Req, Playwright, ScrapingBee, Response}

  describe "get/3 with single module" do
    test "successfully retrieves content with Req" do
      url = Faker.Internet.url()
      opts = [timeout: 5000]
      
      expect(Req, :get, fn ^url, ^opts -> 
        {:ok, %Response{status: :ok, content: "<html>Content</html>"}}
      end)
      
      assert {:ok, %Response{status: :ok, content: "<html>Content</html>"}} = 
        Retriever.get(Req, url, opts)
    end

    test "handles retriever error" do
      url = Faker.Internet.url()
      
      expect(Req, :get, fn ^url, [] -> 
        {:error, :connection_failed}
      end)
      
      assert {:error, :connection_failed} = Retriever.get(Req, url)
    end

    test "applies responder function to successful response" do
      url = Faker.Internet.url()
      custom_responder = fn response -> 
        {:ok, String.upcase(response.body)}
      end
      
      expect(Playwright, :get, fn ^url, opts -> 
        assert opts[:responder] == custom_responder
        {:ok, %Response{status: :ok, content: "content"}}
      end)
      
      Retriever.get(Playwright, url, responder: custom_responder)
    end
  end

  describe "get/3 with multiple modules" do
    test "tries modules in order until success" do
      url = Faker.Internet.url()
      modules = [Req, Playwright, ScrapingBee]
      
      # First module fails
      expect(Req, :get, fn ^url, [] -> 
        {:error, :timeout}
      end)
      
      # Second module succeeds
      expect(Playwright, :get, fn ^url, [] -> 
        {:ok, %Response{status: :ok, content: "Success"}}
      end)
      
      # Third module should not be called
      reject(&ScrapingBee.get/2)
      
      assert {:ok, %Response{status: :ok, content: "Success"}} = 
        Retriever.get(modules, url)
    end

    test "returns last error if all modules fail" do
      url = Faker.Internet.url()
      modules = [Req, Playwright]
      
      expect(Req, :get, fn ^url, [] -> 
        {:error, :req_failed}
      end)
      
      expect(Playwright, :get, fn ^url, [] -> 
        {:error, :playwright_failed}
      end)
      
      assert {:error, :playwright_failed} = Retriever.get(modules, url)
    end

    test "logs errors when trying multiple modules" do
      url = Faker.Internet.url()
      modules = [Req, Playwright]
      
      expect(Req, :get, fn ^url, [] -> 
        {:error, :connection_error}
      end)
      
      expect(Playwright, :get, fn ^url, [] -> 
        {:ok, %Response{status: :ok, content: "OK"}}
      end)
      
      log = capture_log(fn ->
        assert {:ok, _} = Retriever.get(modules, url)
      end)
      
      assert log =~ "Error with Elixir.Mulberry.Retriever.Req"
      assert log =~ "connection_error"
    end

    test "passes options to all retrievers" do
      url = Faker.Internet.url()
      modules = [Req, Playwright]
      opts = [timeout: 10_000, headers: [{"User-Agent", "Test"}]]
      
      expect(Req, :get, fn ^url, ^opts -> 
        {:error, :failed}
      end)
      
      expect(Playwright, :get, fn ^url, ^opts -> 
        {:ok, %Response{status: :ok, content: "Some content"}}
      end)
      
      assert {:ok, _} = Retriever.get(modules, url, opts)
    end
  end

  describe "default_responder/1" do
    test "returns ok tuple for successful response" do
      response = %Response{status: :ok, content: "Success"}
      assert {:ok, ^response} = Response.default_responder(response)
    end

    test "returns ok tuple for redirect response" do
      response = %Response{status: :ok, content: "Redirect"}
      assert {:ok, ^response} = Response.default_responder(response)
    end

    test "returns error for client error response" do
      response = %Response{status: :failed, content: "Not Found"}
      assert {:error, ^response} = Response.default_responder(response)
    end

    test "returns error for server error response" do
      response = %Response{status: :failed, content: "Server Error"}
      assert {:error, ^response} = Response.default_responder(response)
    end

    test "returns ok for :ok status" do
      response = %Response{status: :ok, content: "OK"}
      assert {:ok, ^response} = Response.default_responder(response)
    end

    test "returns error for :failed status" do
      response = %Response{status: :failed, content: "Error"}
      assert {:error, ^response} = Response.default_responder(response)
    end
  end
end