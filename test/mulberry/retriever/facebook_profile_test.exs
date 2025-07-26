defmodule Mulberry.Retriever.FacebookProfileTest do
  use ExUnit.Case, async: false
  use Mimic

  setup :set_mimic_global

  alias Mulberry.Retriever.FacebookProfile
  alias Mulberry.Retriever.Response

  describe "get/2" do
    test "successfully retrieves Facebook profile data" do
      url = "https://www.facebook.com/copperkettleyqr"
      api_key = "test_api_key"

      # Mock the config to return API key
      expect(Mulberry, :config, fn :scrapecreators_api_key -> api_key end)

      # Mock successful API response
      mock_response = %{
        "id" => "100064027242849",
        "name" => "The Copper Kettle Restaurant",
        "url" => url,
        "gender" => "NEUTER",
        "coverPhoto" => %{
          "focus" => %{"x" => 0.5, "y" => 0.48327464788732},
          "photo" => %{
            "id" => "436705571807014",
            "image" => %{
              "uri" => "https://scontent.xx.fbcdn.net/photo.jpg",
              "width" => 960,
              "height" => 641
            }
          }
        },
        "isBusinessPageActive" => false,
        "profilePhoto" => %{
          "url" => "https://www.facebook.com/photo/?fbid=436705568473681",
          "viewer_image" => %{"height" => 320, "width" => 320},
          "id" => "436705568473681"
        },
        "pageIntro" => "Longstanding local restaurant. Mediterranean specialties",
        "category" => "Pizza place",
        "address" => "1953 Scarth Street, Regina, SK, Canada",
        "email" => "copperkettle.events@gmail.com",
        "links" => [],
        "phone" => "+1 306-525-3545",
        "website" => "http://www.thecopperkettle.online/",
        "services" => "Outdoor seating",
        "priceRange" => "$$",
        "rating" => "90% recommend (205 Reviews)",
        "ratingCount" => 205,
        "likeCount" => 2400,
        "followerCount" => 2700,
        "adLibrary" => %{
          "adStatus" => "This Page is currently running ads.",
          "pageId" => "851606664870954"
        },
        "creationDate" => "October 29, 2014"
      }

      expect(Req, :get, fn api_url, opts ->
        assert api_url == "https://api.scrapecreators.com/v1/facebook/profile"
        assert opts[:headers] == %{"x-api-key" => api_key}
        assert opts[:params] == %{url: url}

        {:ok, %Req.Response{status: 200, body: mock_response}}
      end)

      assert {:ok, response} = FacebookProfile.get(url)
      assert %Response{status: :ok, content: content} = response

      # Verify transformed data
      assert content.id == "100064027242849"
      assert content.name == "The Copper Kettle Restaurant"
      assert content.url == url
      assert content.category == "Pizza place"
      assert content.like_count == 2400
      assert content.follower_count == 2700
      assert content.is_business_page_active == false
    end

    test "handles API error response" do
      url = "https://www.facebook.com/invalid"
      api_key = "test_api_key"

      expect(Mulberry, :config, fn :scrapecreators_api_key -> api_key end)

      expect(Req, :get, fn _, _ ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"error" => "Profile not found"}
         }}
      end)

      assert {:error, response} = FacebookProfile.get(url)
      assert response.status == :failed
      assert response.content == nil
    end

    test "handles HTTP error status" do
      url = "https://www.facebook.com/test"
      api_key = "test_api_key"

      expect(Mulberry, :config, fn :scrapecreators_api_key -> api_key end)

      expect(Req, :get, fn _, _ ->
        {:ok, %Req.Response{status: 401, body: "Unauthorized"}}
      end)

      assert {:error, response} = FacebookProfile.get(url)
      assert response.status == :failed
      assert response.content == nil
    end

    test "handles network error" do
      url = "https://www.facebook.com/test"
      api_key = "test_api_key"

      expect(Mulberry, :config, fn :scrapecreators_api_key -> api_key end)

      expect(Req, :get, fn _, _ ->
        {:error, %Mint.TransportError{reason: :timeout}}
      end)

      assert {:error, response} = FacebookProfile.get(url)
      assert response.status == :failed
      assert response.content == nil
    end

    test "handles missing API key" do
      url = "https://www.facebook.com/test"

      expect(Mulberry, :config, fn :scrapecreators_api_key -> nil end)

      # Should not make any HTTP request
      reject(&Req.get/2)

      assert {:error, response} = FacebookProfile.get(url)
      assert response.status == :failed
      assert response.content == nil
    end

    test "applies custom responder function" do
      url = "https://www.facebook.com/test"
      api_key = "test_api_key"

      custom_responder = fn response ->
        {:ok, Map.put(response, :custom, true)}
      end

      expect(Mulberry, :config, fn :scrapecreators_api_key -> api_key end)

      expect(Req, :get, fn _, _ ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"id" => "123", "name" => "Test"}
         }}
      end)

      assert {:ok, response} = FacebookProfile.get(url, responder: custom_responder)
      assert response.custom == true
      assert response.status == :ok
    end

    test "handles unexpected response format" do
      url = "https://www.facebook.com/test"
      api_key = "test_api_key"

      expect(Mulberry, :config, fn :scrapecreators_api_key -> api_key end)

      expect(Req, :get, fn _, _ ->
        {:ok, %Req.Response{status: 200, body: "unexpected string response"}}
      end)

      assert {:error, response} = FacebookProfile.get(url)
      assert response.status == :failed
      assert response.content == nil
    end
  end

  describe "data transformation" do
    test "transforms all fields correctly" do
      url = "https://www.facebook.com/test"
      api_key = "test_api_key"

      expect(Mulberry, :config, fn :scrapecreators_api_key -> api_key end)

      # Complete API response
      api_response = %{
        "id" => "12345",
        "name" => "Test Page",
        "url" => url,
        "gender" => "MALE",
        "coverPhoto" => %{"photo" => %{"id" => "cover123"}},
        "profilePhoto" => %{"id" => "profile123"},
        "isBusinessPageActive" => true,
        "pageIntro" => "Test intro",
        "category" => "Business",
        "address" => "123 Test St",
        "email" => "test@example.com",
        "links" => ["https://test.com"],
        "phone" => "+1234567890",
        "website" => "https://test.com",
        "services" => "Test services",
        "priceRange" => "$$$",
        "rating" => "5 stars",
        "ratingCount" => 100,
        "likeCount" => 5000,
        "followerCount" => 6000,
        "adLibrary" => %{"adStatus" => "Active"},
        "creationDate" => "January 1, 2020"
      }

      expect(Req, :get, fn _, _ ->
        {:ok, %Req.Response{status: 200, body: api_response}}
      end)

      assert {:ok, response} = FacebookProfile.get(url)
      content = response.content

      # Verify all fields are transformed correctly
      assert content.id == "12345"
      assert content.name == "Test Page"
      assert content.url == url
      assert content.gender == "MALE"
      assert content.cover_photo == %{"photo" => %{"id" => "cover123"}}
      assert content.profile_photo == %{"id" => "profile123"}
      assert content.is_business_page_active == true
      assert content.page_intro == "Test intro"
      assert content.category == "Business"
      assert content.address == "123 Test St"
      assert content.email == "test@example.com"
      assert content.links == ["https://test.com"]
      assert content.phone == "+1234567890"
      assert content.website == "https://test.com"
      assert content.services == "Test services"
      assert content.price_range == "$$$"
      assert content.rating == "5 stars"
      assert content.rating_count == 100
      assert content.like_count == 5000
      assert content.follower_count == 6000
      assert content.ad_library == %{"adStatus" => "Active"}
      assert content.creation_date == "January 1, 2020"
    end

    test "handles missing optional fields" do
      url = "https://www.facebook.com/test"
      api_key = "test_api_key"

      expect(Mulberry, :config, fn :scrapecreators_api_key -> api_key end)

      # Minimal API response
      api_response = %{
        "id" => "12345",
        "name" => "Test Page",
        "url" => url
      }

      expect(Req, :get, fn _, _ ->
        {:ok, %Req.Response{status: 200, body: api_response}}
      end)

      assert {:ok, response} = FacebookProfile.get(url)
      content = response.content

      # Required fields
      assert content.id == "12345"
      assert content.name == "Test Page"
      assert content.url == url

      # Optional fields should be nil or have defaults
      assert content.gender == nil
      assert content.is_business_page_active == false
      assert content.links == []
    end
  end
end
