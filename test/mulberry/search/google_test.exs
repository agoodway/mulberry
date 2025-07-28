defmodule Mulberry.Search.GoogleTest do
  use ExUnit.Case, async: false
  use Mimic
  
  setup :set_mimic_global
  doctest Mulberry.Search.Google

  alias Mulberry.Search.Google
  alias Mulberry.Document.WebPage

  describe "search/3" do
    setup do
      # Set test value
      Application.put_env(:mulberry, :scrapecreators_api_key,
        "test_api_key"
      ) 
    end
    test "searches successfully with valid API key" do
      query = Faker.Lorem.words(3) |> Enum.join(" ")
      limit = 5
      api_key = Application.get_env(:mulberry, :scrapecreators_api_key)

      expect(Mulberry.Retriever, :get, fn Mulberry.Retriever.Req, url, opts ->
        assert url == "https://api.scrapecreators.com/v1/google/search"
        headers = opts[:headers]
        assert {"x-api-key", ^api_key} = List.keyfind(headers, "x-api-key", 0)
        params = opts[:params]
        assert params.query == query
        
        {:ok, %Mulberry.Retriever.Response{
          status: :ok,
          content: Jason.encode!(%{
            "success" => true,
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
          })
        }}
      end)
      
      {:ok, response} = Google.search(query, limit)
      assert response =~ "results"
    end

    test "searches with region parameter" do
      query = Faker.Lorem.word()
      api_key = Faker.UUID.v4()
      region = "UK"
      
      Application.put_env(:mulberry, :scrapecreators_api_key, api_key)
      
      expect(Mulberry.Retriever, :get, fn Mulberry.Retriever.Req, url, opts ->
        assert url == "https://api.scrapecreators.com/v1/google/search"
        params = opts[:params]
        assert params.query == query
        assert params.region == region
        
        {:ok, %Mulberry.Retriever.Response{
          status: :ok,
          content: Jason.encode!(%{
            "success" => true,
            "results" => []
          })
        }}
      end)
      
      {:ok, _response} = Google.search(query, 10, region: region)
      
      Application.delete_env(:mulberry, :scrapecreators_api_key)
    end

    test "handles empty results" do
      query = Faker.Lorem.word()
      expect(Mulberry.Retriever, :get, fn Mulberry.Retriever.Req, _, _ ->
        {:ok, %Mulberry.Retriever.Response{
          status: :ok,
          content: Jason.encode!(%{"success" => true, "results" => []})
        }}
      end)
      
      assert {:ok, response} = Google.search(query, 10)
      assert response =~ "results"
    end

    test "handles missing API key" do
      # Store original values
      _original_app_config = Application.get_env(:mulberry, :scrapecreators_api_key)
      _original_env = System.get_env("SCRAPECREATORS_API_KEY")
      
      # Clear both app config and env var
      Application.delete_env(:mulberry, :scrapecreators_api_key)
      System.delete_env("SCRAPECREATORS_API_KEY")
      
      # When API key is missing, the API will return an error
      expect(Mulberry.Retriever, :get, fn Mulberry.Retriever.Req, _, opts -> 
        # Check that the token is nil
        headers = Keyword.get(opts, :headers, [])
        assert {"x-api-key", nil} in headers
        
        {:error, %Mulberry.Retriever.Response{
          status: :failed,
          content: nil
        }}
      end)
      
      assert {:error, _} = Google.search("test", 10)
    end

    test "handles API error response" do
      query = Faker.Lorem.word()
      expect(Mulberry.Retriever, :get, fn Mulberry.Retriever.Req, _, _ ->
        {:error, %Mulberry.Retriever.Response{
          status: :failed,
          content: nil
        }}
      end)
      
      assert {:error, response} = Google.search(query, 10)
      assert response.status == :failed
    end

    test "handles API failure response" do
      query = Faker.Lorem.word()
      expect(Mulberry.Retriever, :get, fn Mulberry.Retriever.Req, _, _ ->
        {:ok, %Mulberry.Retriever.Response{
          status: :ok,
          content: Jason.encode!(%{"success" => false, "error" => "Invalid API key"})
        }}
      end)
      
      assert {:ok, response} = Google.search(query, 10)
      parsed = Jason.decode!(response)
      assert parsed["success"] == false
    end
  end

  describe "to_documents/1" do
    test "converts search results to WebPage documents" do
      results = %{
        "success" => true,
        "results" => [
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
      }
      
      assert {:ok, documents} = Google.to_documents(results)
      
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
      results = %{
        "success" => true,
        "results" => [
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
      }
      
      assert {:ok, documents} = Google.to_documents(results)
      
      assert length(documents) == 2
      
      [first, second] = documents
      assert first.title == nil
      assert first.description == nil
      
      assert second.title == "Only Title"
      assert second.description == nil
    end

    test "handles empty results list" do
      results = %{
        "success" => true,
        "results" => []
      }
      
      assert {:ok, []} = Google.to_documents(results)
    end

    test "handles API failure response" do
      response = %{
        "success" => false,
        "error" => "Invalid API key"
      }
      
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, :search_failed} = Google.to_documents(response)
      end)
    end

    test "handles unexpected response format" do
      response = %{"unexpected" => "format"}
      
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, :parse_search_results_failed} = Google.to_documents(response)
      end)
    end

    test "handles results without URLs" do
      results = %{
        "success" => true,
        "results" => [
          %{
            "title" => "Has URL",
            "url" => "https://example.com",
            "description" => "Has description"
          },
          %{
            "title" => "No URL",
            "description" => "Missing URL"
            # Missing URL
          }
        ]
      }
      
      assert {:ok, documents} = Google.to_documents(results)
      
      assert length(documents) == 2
      [first, second] = documents
      assert first.url == "https://example.com"
      assert second.url == nil
    end
  end
end
