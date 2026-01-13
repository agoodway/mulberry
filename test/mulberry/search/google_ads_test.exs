defmodule Mulberry.Search.GoogleAdsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Mulberry.Document.GoogleAd
  alias Mulberry.Search.GoogleAds

  describe "search/3" do
    setup do
      Application.put_env(:mulberry, :scrapecreators_api_key, "test_api_key")
      :ok
    end

    test "searches for ads by domain" do
      expect(Mulberry.Retriever, :get, fn _retriever, url, opts ->
        assert url == "https://api.scrapecreators.com/v1/google/company/ads"
        assert opts[:params] == %{domain: "lululemon.com"}
        assert opts[:headers] == [{"x-api-key", "test_api_key"}]

        {:ok,
         %Mulberry.Retriever.Response{
           status: :ok,
           content: %{
             "ads" => [
               %{
                 "advertiserId" => "AR01614014350098432001",
                 "creativeId" => "CR10449491775734153217",
                 "format" => "text",
                 "adUrl" =>
                   "https://adstransparency.google.com/advertiser/AR01614014350098432001/creative/CR10449491775734153217",
                 "advertiserName" => "Lululemon Athletica Canada Inc.",
                 "domain" => "lululemon.com",
                 "firstShown" => "2023-12-29T21:59:16.000Z",
                 "lastShown" => "2025-03-28T01:46:12.000Z"
               }
             ],
             "cursor" => "CgoAP7znOo9RPjf%2FEhD5utgx8m75NrTTbU0AAAAAGgn8%2BJyW%2BJQK40A%3D",
             "success" => true,
             "statusCode" => 200
           }
         }}
      end)

      assert {:ok, response} = GoogleAds.search("lululemon.com")
      assert response["ads"]
      assert length(response["ads"]) == 1
      assert response["cursor"]
    end

    test "searches with advertiser_id" do
      expect(Mulberry.Retriever, :get, fn _retriever, _url, opts ->
        assert opts[:params] == %{advertiser_id: "AR01614014350098432001"}

        {:ok,
         %Mulberry.Retriever.Response{
           status: :ok,
           content: %{
             "ads" => [],
             "success" => true
           }
         }}
      end)

      assert {:ok, _response} = GoogleAds.search(nil, 20, advertiser_id: "AR01614014350098432001")
    end

    test "searches political ads with region" do
      expect(Mulberry.Retriever, :get, fn _retriever, _url, opts ->
        assert opts[:params] == %{
                 domain: "example.com",
                 topic: "political",
                 region: "US"
               }

        {:ok,
         %Mulberry.Retriever.Response{
           status: :ok,
           content: %{
             "ads" => [],
             "success" => true
           }
         }}
      end)

      assert {:ok, _response} =
               GoogleAds.search("example.com", 20, topic: "political", region: "US")
    end

    test "paginates with cursor" do
      expect(Mulberry.Retriever, :get, fn _retriever, _url, opts ->
        assert opts[:params][:cursor] == "test_cursor"

        {:ok,
         %Mulberry.Retriever.Response{
           status: :ok,
           content: %{
             "ads" => [],
             "success" => true
           }
         }}
      end)

      assert {:ok, _response} = GoogleAds.search("example.com", 20, cursor: "test_cursor")
    end

    test "handles retriever error" do
      expect(Mulberry.Retriever, :get, fn _retriever, _url, _opts ->
        {:error, :network_error}
      end)

      assert {:error, :network_error} = GoogleAds.search("example.com")
    end

    test "validates that either domain or advertiser_id is provided" do
      assert {:error, :missing_required_parameter} = GoogleAds.search(nil)
      assert {:error, :missing_required_parameter} = GoogleAds.search(nil, 20, [])
    end

    test "handles rate limiting" do
      expect(Mulberry.Retriever, :get, fn _retriever, _url, _opts ->
        {:error, %{status: :rate_limited}}
      end)

      assert {:error, :rate_limited} = GoogleAds.search("example.com")
    end
  end

  describe "to_documents/1" do
    test "converts ads to GoogleAd documents" do
      results = %{
        "ads" => [
          %{
            "advertiserId" => "AR01614014350098432001",
            "creativeId" => "CR10449491775734153217",
            "format" => "text",
            "adUrl" =>
              "https://adstransparency.google.com/advertiser/AR01614014350098432001/creative/CR10449491775734153217",
            "advertiserName" => "Lululemon Athletica Canada Inc.",
            "domain" => "lululemon.com",
            "firstShown" => "2023-12-29T21:59:16.000Z",
            "lastShown" => "2025-03-28T01:46:12.000Z"
          },
          %{
            "advertiserId" => "AR01614014350098432001",
            "creativeId" => "CR08077733302133325825",
            "format" => "video",
            "adUrl" =>
              "https://adstransparency.google.com/advertiser/AR01614014350098432001/creative/CR08077733302133325825",
            "advertiserName" => "Lululemon Athletica Canada Inc.",
            "domain" => "lululemon.com",
            "firstShown" => "2025-02-03T19:49:57.000Z",
            "lastShown" => "2025-03-28T01:43:03.000Z"
          }
        ]
      }

      assert {:ok, docs} = GoogleAds.to_documents(results)
      assert length(docs) == 2
      assert [%GoogleAd{} = ad1, %GoogleAd{} = ad2] = docs

      # Check first ad
      assert ad1.advertiser_id == "AR01614014350098432001"
      assert ad1.creative_id == "CR10449491775734153217"
      assert ad1.format == "text"
      assert ad1.advertiser_name == "Lululemon Athletica Canada Inc."
      assert ad1.domain == "lululemon.com"

      # Check second ad
      assert ad2.format == "video"
      assert ad2.creative_id == "CR08077733302133325825"
    end

    test "handles empty results" do
      assert {:ok, []} = GoogleAds.to_documents(%{"ads" => []})
    end

    test "handles API error response" do
      results = %{"error" => "Invalid API key"}
      assert {:error, :api_error} = GoogleAds.to_documents(results)
    end

    test "handles unexpected response format" do
      assert {:error, :invalid_response_format} =
               GoogleAds.to_documents(%{"unexpected" => "format"})
    end
  end
end
