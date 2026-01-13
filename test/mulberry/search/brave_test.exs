defmodule Mulberry.Search.BraveTest do
  use ExUnit.Case, async: false
  use Mimic

  setup :set_mimic_global
  doctest Mulberry.Search.Brave

  alias Mulberry.Search.Brave
  alias Mulberry.Document.WebPage

  describe "search/2" do
    setup do
      # Set test value
      Application.put_env(:mulberry, :brave_api_key, "test_api_key")
    end

    test "searches successfully with valid API key" do
      query = Faker.Lorem.words(3) |> Enum.join(" ")
      limit = 5

      expect(Mulberry.Retriever, :get, fn Mulberry.Retriever.Req, url, opts ->
        assert url == "https://api.search.brave.com/res/v1/web/search"
        _headers = opts[:headers]

        {:ok,
         %Mulberry.Retriever.Response{
           status: :ok,
           content:
             Jason.encode!(%{
               "web" => %{
                 "results" => [
                   %{
                     "title" => "Result 1",
                     "url" => "https://example1.com",
                     "description" => "Description 1"
                   },
                   %{
                     "title" => "Result 2",
                     "url" => "https://example2.com",
                     "description" => "Description 2"
                   }
                 ]
               }
             })
         }}
      end)

      {:ok, response} = Brave.search(query, limit)
      assert response.status == :ok
      assert response.content =~ "results"
    end

    test "handles empty results" do
      query = Faker.Lorem.word()

      expect(Mulberry.Retriever, :get, fn Mulberry.Retriever.Req, _, _ ->
        {:ok,
         %Mulberry.Retriever.Response{
           status: :ok,
           content: Jason.encode!(%{"web" => %{"results" => []}})
         }}
      end)

      assert {:ok, response} = Brave.search(query, 10)
      assert response.content =~ "results"
    end

    test "handles missing web results" do
      query = Faker.Lorem.word()
      _api_key = Faker.UUID.v4()

      expect(Mulberry.Retriever, :get, fn Mulberry.Retriever.Req, _, _ ->
        {:ok,
         %Mulberry.Retriever.Response{
           status: :ok,
           content: Jason.encode!(%{})
         }}
      end)

      assert {:ok, response} = Brave.search(query, 10)
      # With empty body, to_documents would return an error
      assert response.content == "{}"
    end

    test "handles missing API key" do
      # Clear both app config and env var
      Application.delete_env(:mulberry, :brave_api_key)
      original_env = System.get_env("BRAVE_API_KEY")
      System.delete_env("BRAVE_API_KEY")

      # When API key is missing, the API will return an error
      expect(Mulberry.Retriever, :get, fn Mulberry.Retriever.Req, _, opts ->
        # Check that the token is nil
        headers = Keyword.get(opts, :headers, [])
        assert {"X-Subscription-Token", nil} in headers

        {:error,
         %Mulberry.Retriever.Response{
           status: :failed,
           content: nil
         }}
      end)

      assert {:error, _} = Brave.search("test", 10)

      # Restore original env if it existed
      if original_env do
        System.put_env("BRAVE_API_KEY", original_env)
      end
    end

    test "handles API error response" do
      query = Faker.Lorem.word()
      _api_key = Faker.UUID.v4()

      expect(Mulberry.Retriever, :get, fn Mulberry.Retriever.Req, _, _ ->
        {:error,
         %Mulberry.Retriever.Response{
           status: :failed,
           content: nil
         }}
      end)

      assert {:error, response} = Brave.search(query, 10)
      assert response.status == :failed
    end
  end

  describe "to_documents/1" do
    test "converts search results to WebPage documents" do
      results = [
        %{
          "title" => "First Result",
          "url" => "https://example1.com",
          "description" => "First description"
        },
        %{
          "title" => "Second Result",
          "url" => "https://example2.com",
          "description" => "Second description"
        }
      ]

      assert {:ok, documents} = Brave.to_documents(results)

      assert length(documents) == 2
      assert Enum.all?(documents, &match?(%WebPage{}, &1))

      [first, second] = documents
      assert first.url == "https://example1.com"
      assert first.title == "First Result"
      assert first.description == "First description"

      assert second.url == "https://example2.com"
      assert second.title == "Second Result"
      assert second.description == "Second description"
    end

    test "handles results with missing fields" do
      results = [
        %{
          "url" => "https://example.com"
          # Missing title and description
        },
        %{
          "title" => "Only Title",
          "url" => "https://example2.com"
          # Missing description
        }
      ]

      assert {:ok, documents} = Brave.to_documents(results)

      assert length(documents) == 2

      [first, second] = documents
      assert first.title == nil
      assert first.summary == nil

      assert second.title == "Only Title"
      assert second.summary == nil
    end

    test "handles empty results list" do
      assert Brave.to_documents([]) == {:ok, []}
    end

    test "handles results without URLs" do
      results = [
        %{
          "title" => "Has URL",
          "url" => "https://example.com"
        },
        %{
          "title" => "No URL"
          # Missing URL
        }
      ]

      assert {:ok, documents} = Brave.to_documents(results)

      assert length(documents) == 2
      [first, second] = documents
      assert first.url == "https://example.com"
      assert second.url == nil
    end

    test "handles Brave API response format with web results" do
      response = %{
        "web" => %{
          "results" => [
            %{
              "title" => "Test Result",
              "url" => "https://example.com",
              "description" => "Test description"
            }
          ]
        },
        "type" => "search"
      }

      assert {:ok, documents} = Brave.to_documents(response)
      assert length(documents) == 1
      assert [%WebPage{url: "https://example.com", title: "Test Result"}] = documents
    end

    test "handles Brave API response format without web results" do
      response = %{
        "type" => "search",
        "mixed" => %{"main" => [], "side" => [], "top" => []},
        "query" => %{"original" => "test query"}
      }

      assert {:ok, []} = Brave.to_documents(response)
    end

    test "handles unexpected response format" do
      response = %{"unexpected" => "format"}

      assert {:error, :parse_search_results_failed} = Brave.to_documents(response)
    end
  end
end
