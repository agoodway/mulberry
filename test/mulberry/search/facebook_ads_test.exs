defmodule Mulberry.Search.FacebookAdsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Mulberry.Search.FacebookAds
  alias Mulberry.Retriever
  alias Mulberry.Retriever.Response

  describe "search/3" do
    setup do
      # Set test value
      Application.put_env(:mulberry, :scrapecreators_api_key, "test_api_key")
    end

    test "performs basic search with company name" do
      expect(Retriever, :get, fn module, url, opts ->
        assert module == Mulberry.Retriever.Req
        assert url == "https://api.scrapecreators.com/v1/facebook/adLibrary/company/ads"
        
        # Check params
        assert opts[:params] == %{companyName: "Nike"}
        
        # Check headers
        headers = opts[:headers]
        assert {"x-api-key", "test_api_key"} in headers
        
        {:ok, %Response{status: :ok, content: %{"results" => []}}}
      end)

      assert {:ok, %{"results" => []}} = FacebookAds.search("Nike")
    end

    test "performs search with page ID" do
      expect(Retriever, :get, fn _module, _url, opts ->
        params = opts[:params]
        assert params.pageId == "123456789"
        refute Map.has_key?(params, :companyName)
        
        {:ok, %Response{status: :ok, content: %{"results" => []}}}
      end)

      assert {:ok, _} = FacebookAds.search("123456789", 20, search_by: :page_id)
    end

    test "includes optional parameters when provided" do
      expect(Retriever, :get, fn _module, _url, opts ->
        params = opts[:params]
        assert params.companyName == "Apple"
        assert params.country == "US"
        assert params.status == "ACTIVE"
        assert params.media_type == "video"
        assert params.cursor == "next_page_cursor"
        assert params.trim == true
        
        {:ok, %Response{status: :ok, content: %{"results" => []}}}
      end)

      opts = [
        country: "US",
        status: "ACTIVE",
        media_type: "video",
        cursor: "next_page_cursor",
        trim: true
      ]
      
      assert {:ok, _} = FacebookAds.search("Apple", 20, opts)
    end

    test "uses custom retriever when specified" do
      mock_retriever = :custom_retriever
      
      expect(Retriever, :get, fn module, _url, _opts ->
        assert module == mock_retriever
        {:ok, %Response{status: :ok, content: %{"results" => []}}}
      end)

      assert {:ok, _} = FacebookAds.search("Test", 20, retriever: mock_retriever)
    end
  end

  describe "to_documents/1" do
    test "converts results to FacebookAd documents" do
      results = %{
        "results" => [
          %{
            "ad_archive_id" => "1162496978867592",
            "ad_id" => nil,
            "collation_id" => "596215693307098",
            "collation_count" => 3,
            "page_id" => "367152833370567",
            "page_name" => "Instagram",
            "page_is_deleted" => false,
            "is_active" => true,
            "start_date" => 1_740_643_200,
            "end_date" => 1_740_902_400,
            "categories" => ["UNKNOWN"],
            "entity_type" => "PERSON_PROFILE",
            "publisher_platform" => ["INSTAGRAM"],
            "currency" => "",
            "targeted_or_reached_countries" => [],
            "contains_sensitive_content" => false,
            "has_user_reported" => false,
            "report_count" => nil,
            "is_aaa_eligible" => false,
            "impressions_with_index" => %{
              "impressions_text" => nil,
              "impressions_index" => -1
            },
            "snapshot" => %{
              "body" => %{
                "text" => "Bendito el día que seguí a mi compa en Insta :)"
              },
              "caption" => "fb.me",
              "cta_text" => "Learn more",
              "cta_type" => "LEARN_MORE",
              "link_url" => "http://fb.me/1171219090745394",
              "link_description" => nil,
              "title" => nil,
              "byline" => nil,
              "display_format" => "VIDEO",
              "images" => [],
              "videos" => [
                %{
                  "video_hd_url" => "https://example.com/video.mp4",
                  "video_preview_image_url" => "https://example.com/preview.jpg"
                }
              ],
              "branded_content" => %{
                "page_profile_uri" => "https://www.facebook.com/instagram/"
              }
            }
          }
        ],
        "cursor" => "AQHRBUAxNmFlxBVMFL6uTb1ICFsV65O4SqmPbcVZJhiveBpPS1hFHAmL6yCJcF760cXP"
      }

      {:ok, documents} = FacebookAds.to_documents(results)
      
      assert length(documents) == 1
      
      [doc] = documents
      assert doc.__struct__ == Mulberry.Document.FacebookAd
      assert doc.ad_archive_id == "1162496978867592"
      assert doc.page_name == "Instagram"
      assert doc.is_active == true
      assert doc.body_text == "Bendito el día que seguí a mi compa en Insta :)"
      assert doc.cta_text == "Learn more"
      assert doc.link_url == "http://fb.me/1171219090745394"
      assert doc.publisher_platform == ["INSTAGRAM"]
      assert length(doc.videos) == 1
    end

    test "handles empty results" do
      assert {:ok, []} = FacebookAds.to_documents(%{"results" => []})
    end

    test "handles error responses" do
      error_response = %{"error" => "Invalid API key"}
      assert {:error, :search_failed} = FacebookAds.to_documents(error_response)
    end

    test "handles unexpected response format" do
      assert {:error, :parse_search_results_failed} = FacebookAds.to_documents(%{"unexpected" => "format"})
    end

    test "handles missing snapshot data gracefully" do
      results = %{
        "results" => [
          %{
            "ad_archive_id" => "123",
            "page_id" => "456",
            "page_name" => "Test Page",
            "is_active" => true,
            "publisher_platform" => ["FACEBOOK"],
            "snapshot" => %{}
          }
        ]
      }

      {:ok, [doc]} = FacebookAds.to_documents(results)
      assert doc.body_text == nil
      assert doc.cta_text == nil
      assert doc.images == []
      assert doc.videos == []
    end
  end
end
