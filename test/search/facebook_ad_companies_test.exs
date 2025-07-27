defmodule Mulberry.Search.FacebookAdCompaniesTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Mulberry.Search.FacebookAdCompanies
  alias Mulberry.Retriever
  alias Mulberry.Retriever.Response

  describe "search/3" do
    test "performs basic search with query parameter" do
      expect(Retriever, :get, fn module, url, opts ->
        assert module == Mulberry.Retriever.Req
        assert url == "https://api.scrapecreators.com/v1/facebook/adLibrary/search/companies"
        
        # Check params
        assert opts[:params] == %{query: "Nike"}
        
        # Check headers
        headers = opts[:headers]
        assert {"x-api-key", "test_api_key"} in headers
        
        {:ok, %Response{status: :ok, content: %{"searchResults" => []}}}
      end)

      Application.put_env(:mulberry, :scrapecreators_api_key, "test_api_key")
      assert {:ok, %{"searchResults" => []}} = FacebookAdCompanies.search("Nike")
    end

    test "uses custom retriever when specified" do
      mock_retriever = :custom_retriever
      
      expect(Retriever, :get, fn module, _url, _opts ->
        assert module == mock_retriever
        {:ok, %Response{status: :ok, content: %{"searchResults" => []}}}
      end)

      Application.put_env(:mulberry, :scrapecreators_api_key, "test_api_key")
      assert {:ok, _} = FacebookAdCompanies.search("Test", 20, retriever: mock_retriever)
    end

    test "handles API errors gracefully" do
      expect(Retriever, :get, fn _module, _url, _opts ->
        {:error, "API request failed"}
      end)

      Application.put_env(:mulberry, :scrapecreators_api_key, "test_api_key")
      assert {:error, "API request failed"} = FacebookAdCompanies.search("Test")
    end
  end

  describe "to_documents/1" do
    test "converts search results to FacebookAdCompany documents" do
      results = %{
        "searchResults" => [
          %{
            "page_id" => "51212153078",
            "category" => "Product/service",
            "image_uri" => "https://scontent.ford4-1.fna.fbcdn.net/nike-football.jpg",
            "likes" => 41_136_495,
            "verification" => "BLUE_VERIFIED",
            "name" => "Nike Football",
            "country" => nil,
            "entity_type" => "PERSON_PROFILE",
            "ig_username" => "nikefootball",
            "ig_followers" => 46_451_228,
            "ig_verification" => true,
            "page_alias" => "nikefootball",
            "page_is_deleted" => false
          },
          %{
            "page_id" => "15087023444",
            "category" => "Sportswear Store",
            "image_uri" => "https://scontent.ford4-1.fna.fbcdn.net/nike.jpg",
            "likes" => 39_558_683,
            "verification" => "BLUE_VERIFIED",
            "name" => "Nike",
            "country" => nil,
            "entity_type" => "PERSON_PROFILE",
            "ig_username" => "nike",
            "ig_followers" => 302_060_936,
            "ig_verification" => true,
            "page_alias" => "nike",
            "page_is_deleted" => false
          }
        ]
      }

      {:ok, documents} = FacebookAdCompanies.to_documents(results)
      
      assert length(documents) == 2
      
      [nike_football, nike] = documents
      
      # Verify Nike Football document
      assert nike_football.__struct__ == Mulberry.Document.FacebookAdCompany
      assert nike_football.page_id == "51212153078"
      assert nike_football.name == "Nike Football"
      assert nike_football.category == "Product/service"
      assert nike_football.likes == 41_136_495
      assert nike_football.verification == "BLUE_VERIFIED"
      assert nike_football.ig_username == "nikefootball"
      assert nike_football.ig_followers == 46_451_228
      assert nike_football.ig_verification == true
      assert nike_football.page_is_deleted == false
      
      # Verify Nike document
      assert nike.__struct__ == Mulberry.Document.FacebookAdCompany
      assert nike.page_id == "15087023444"
      assert nike.name == "Nike"
      assert nike.category == "Sportswear Store"
      assert nike.likes == 39_558_683
      assert nike.ig_username == "nike"
      assert nike.ig_followers == 302_060_936
    end

    test "handles empty search results" do
      assert {:ok, []} = FacebookAdCompanies.to_documents(%{"searchResults" => []})
    end

    test "handles error responses" do
      error_response = %{"error" => "Invalid API key"}
      assert {:error, :search_failed} = FacebookAdCompanies.to_documents(error_response)
    end

    test "handles unexpected response format" do
      assert {:error, :parse_search_results_failed} = 
        FacebookAdCompanies.to_documents(%{"unexpected" => "format"})
    end

    test "handles missing optional fields gracefully" do
      results = %{
        "searchResults" => [
          %{
            "page_id" => "123",
            "name" => "Test Company",
            "category" => nil,
            "image_uri" => nil,
            "likes" => nil,
            "verification" => nil,
            "country" => nil,
            "entity_type" => nil,
            "ig_username" => nil,
            "ig_followers" => nil,
            "ig_verification" => false,
            "page_alias" => nil,
            "page_is_deleted" => false
          }
        ]
      }

      {:ok, [doc]} = FacebookAdCompanies.to_documents(results)
      assert doc.page_id == "123"
      assert doc.name == "Test Company"
      assert doc.category == nil
      assert doc.likes == nil
      assert doc.ig_username == nil
      assert doc.ig_verification == false
    end
  end

  describe "integration with Mulberry.search/3" do
    test "works with the high-level search interface" do
      expect(Retriever, :get, fn _module, _url, _opts ->
        {:ok, %Response{
          status: :ok, 
          content: %{
            "searchResults" => [
              %{
                "page_id" => "123",
                "name" => "Example Company",
                "category" => "Technology",
                "likes" => 1000,
                "verification" => "BLUE_VERIFIED",
                "ig_username" => "example",
                "ig_followers" => 5000,
                "ig_verification" => true,
                "page_is_deleted" => false
              }
            ]
          }
        }}
      end)

      Application.put_env(:mulberry, :scrapecreators_api_key, "test_api_key")
      
      # The high-level search function now properly handles the tuple returns
      {:ok, companies} = Mulberry.search(FacebookAdCompanies, "Example", 10)
      
      assert length(companies) == 1
      [company] = companies
      assert company.name == "Example Company"
      assert company.category == "Technology"
    end
  end
end