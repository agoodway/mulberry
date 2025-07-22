defmodule Mulberry.Search.BraveTest do
  use ExUnit.Case, async: true
  use Mimic
  import ExUnit.CaptureLog
  doctest Mulberry.Search.Brave

  alias Mulberry.Search.Brave
  alias Mulberry.Document.WebPage

  describe "search/2" do
    test "searches successfully with valid API key" do
      query = Faker.Lorem.words(3) |> Enum.join(" ")
      limit = 5
      api_key = Faker.UUID.v4()
      
      Application.put_env(:mulberry, :brave_api_key, api_key)
      
      mock_response = %Req.Response{
        status: 200,
        body: %{
          "web" => %{
            "results" => [
              %{
                "title" => Faker.Lorem.sentence(),
                "url" => Faker.Internet.url(),
                "description" => Faker.Lorem.paragraph()
              },
              %{
                "title" => Faker.Lorem.sentence(),
                "url" => Faker.Internet.url(), 
                "description" => Faker.Lorem.paragraph()
              }
            ]
          }
        }
      }
      
      expect(Req, :get!, fn url, opts ->
        assert url == "https://api.search.brave.com/res/v1/web/search"
        assert opts[:params] == [q: query, count: limit]
        assert opts[:headers] == [{"X-Subscription-Token", api_key}]
        mock_response
      end)
      
      results = Brave.search(query, limit)
      assert length(results) == 2
      assert Map.has_key?(hd(results), "title")
      assert Map.has_key?(hd(results), "url")
      
      Application.delete_env(:mulberry, :brave_api_key)
    end

    test "handles empty results" do
      query = Faker.Lorem.word()
      api_key = Faker.UUID.v4()
      
      Application.put_env(:mulberry, :brave_api_key, api_key)
      
      expect(Req, :get!, fn _, _ ->
        %Req.Response{
          status: 200,
          body: %{"web" => %{"results" => []}}
        }
      end)
      
      assert Brave.search(query, 10) == []
      
      Application.delete_env(:mulberry, :brave_api_key)
    end

    test "handles missing web results" do
      query = Faker.Lorem.word()
      api_key = Faker.UUID.v4()
      
      Application.put_env(:mulberry, :brave_api_key, api_key)
      
      expect(Req, :get!, fn _, _ ->
        %Req.Response{
          status: 200,
          body: %{}
        }
      end)
      
      assert Brave.search(query, 10) == []
      
      Application.delete_env(:mulberry, :brave_api_key)
    end

    test "raises error when API key is not configured" do
      Application.delete_env(:mulberry, :brave_api_key)
      
      assert_raise RuntimeError, ~r/brave_api_key is not configured/, fn ->
        Brave.search("test", 10)
      end
    end

    test "handles API error response" do
      query = Faker.Lorem.word()
      api_key = Faker.UUID.v4()
      
      Application.put_env(:mulberry, :brave_api_key, api_key)
      
      expect(Req, :get!, fn _, _ ->
        raise Req.Error, "API Error"
      end)
      
      assert_raise Req.Error, fn ->
        Brave.search(query, 10)
      end
      
      Application.delete_env(:mulberry, :brave_api_key)
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
      
      documents = Brave.to_documents(results)
      
      assert length(documents) == 2
      assert Enum.all?(documents, &match?(%WebPage{}, &1))
      
      [first, second] = documents
      assert first.url == "https://example1.com"
      assert first.title == "First Result"
      assert first.summary == "First description"
      
      assert second.url == "https://example2.com"
      assert second.title == "Second Result"
      assert second.summary == "Second description"
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
      
      documents = Brave.to_documents(results)
      
      assert length(documents) == 2
      
      [first, second] = documents
      assert first.title == nil
      assert first.summary == nil
      
      assert second.title == "Only Title"
      assert second.summary == nil
    end

    test "handles empty results list" do
      assert Brave.to_documents([]) == []
    end

    test "filters out results without URLs" do
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
      
      documents = Brave.to_documents(results)
      
      assert length(documents) == 1
      assert hd(documents).url == "https://example.com"
    end
  end
end