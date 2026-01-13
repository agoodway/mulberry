defmodule Mulberry.Retriever.GoogleAdTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Mulberry.Retriever.GoogleAd

  describe "get/2" do
    setup do
      # Store original value if it exists
      original_value = Application.get_env(:mulberry, :scrapecreators_api_key)

      # Set test value
      Application.put_env(:mulberry, :scrapecreators_api_key, "test_api_key")

      on_exit(fn ->
        # Restore original value or delete
        if original_value do
          Application.put_env(:mulberry, :scrapecreators_api_key, original_value)
        else
          Application.delete_env(:mulberry, :scrapecreators_api_key)
        end
      end)
    end

    test "fetches Google ad details successfully" do
      ad_url =
        "https://adstransparency.google.com/advertiser/AR01614014350098432001/creative/CR07443539616616939521"

      expect(Req, :get, fn url, opts ->
        assert url == "https://api.scrapecreators.com/v1/google/ad"
        # Check that the headers contain the expected API key
        headers = opts[:headers]

        assert headers["x-api-key"] == "test_api_key",
               "Expected headers to contain x-api-key with test_api_key, but got: #{inspect(headers)}"

        assert opts[:params] == %{url: ad_url}

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "success" => true,
             "advertiserId" => "AR01614014350098432001",
             "creativeId" => "CR07443539616616939521",
             "firstShown" => nil,
             "lastShown" => "2025-06-18T18:09:00.000Z",
             "format" => "text",
             "overallImpressions" => %{
               "min" => nil,
               "max" => nil
             },
             "creativeRegions" => [
               %{
                 "regionCode" => "US",
                 "regionName" => "United States"
               }
             ],
             "regionStats" => [
               %{
                 "regionCode" => "US",
                 "regionName" => "United States",
                 "firstShown" => nil,
                 "lastShown" => "2025-06-18T05:00:00.000Z",
                 "impressions" => %{},
                 "platformImpressions" => []
               }
             ],
             "variations" => [
               %{
                 "destinationUrl" => "shop.lululemon.com/gifts-for-all",
                 "headline" => "lululemonⓇ Official Site - Best Birthday Gifts",
                 "description" =>
                   "Find The Perfect Gifts At lululemon . We Have You Covered . Shop Online For Your Gifts . Birthday Gifts For Everyone ...",
                 "allText" =>
                   "Sponsored Ω lululemon shop.lululemon.com/gifts-for-all lululemonⓇ Official Site - Best Birthday Gifts Find The Perfect Gifts At lululemon . We Have You Covered . Shop Online For Your Gifts . Birthday Gifts For Everyone ...",
                 "imageUrl" =>
                   "https://tpc.googlesyndication.com/archive/simgad/2201045439314643090"
               },
               %{
                 "destinationUrl" => "shop.lululemon.com",
                 "headline" => "Work Pants, But Stretchy",
                 "description" =>
                   "Move In Lightweight, Comfortable Work Pants That Take Your Day In New Directions."
               }
             ]
           }
         }}
      end)

      assert {:ok, response} = GoogleAd.get(ad_url)
      assert response.status == :ok
      assert response.content["advertiserId"] == "AR01614014350098432001"
      assert response.content["creativeId"] == "CR07443539616616939521"
      assert length(response.content["variations"]) == 2
      assert response.content["creativeRegions"]
    end

    test "handles API error response" do
      expect(Req, :get, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "success" => false,
             "error" => "Invalid ad URL"
           }
         }}
      end)

      assert {:error, response} = GoogleAd.get("invalid_url")
      assert response.status == :failed
      assert response.content == nil
    end

    test "handles HTTP error status" do
      expect(Req, :get, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 404,
           body: %{"error" => "Not found"}
         }}
      end)

      assert {:error, response} = GoogleAd.get("https://example.com/ad")
      assert response.status == :failed
      assert response.content == nil
    end

    test "handles rate limiting" do
      expect(Req, :get, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 429,
           body: %{"error" => "Rate limit exceeded"}
         }}
      end)

      assert {:error, response} = GoogleAd.get("https://example.com/ad")
      assert response.status == :rate_limited
      assert response.content == nil
    end

    test "handles network error" do
      expect(Req, :get, fn _url, _opts ->
        {:error, %Mint.TransportError{reason: :nxdomain}}
      end)

      assert {:error, response} = GoogleAd.get("https://example.com/ad")
      assert response.status == :failed
      assert response.content == nil
    end

    test "handles missing API key" do
      Application.delete_env(:mulberry, :scrapecreators_api_key)

      assert {:error, response} = GoogleAd.get("https://example.com/ad")
      assert response.status == :failed
      assert response.content == nil
    end

    test "handles response without explicit success field" do
      expect(Req, :get, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "advertiserId" => "AR01614014350098432001",
             "creativeId" => "CR07443539616616939521",
             "format" => "text"
           }
         }}
      end)

      assert {:ok, response} = GoogleAd.get("https://example.com/ad")
      assert response.status == :ok
      assert response.content["advertiserId"] == "AR01614014350098432001"
    end

    test "handles unexpected response format" do
      expect(Req, :get, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: "unexpected string response"
         }}
      end)

      assert {:error, response} = GoogleAd.get("https://example.com/ad")
      assert response.status == :failed
      assert response.content == nil
    end

    test "uses custom responder" do
      custom_responder = fn response ->
        {:custom, response}
      end

      expect(Req, :get, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "success" => true,
             "advertiserId" => "AR01614014350098432001"
           }
         }}
      end)

      assert {:custom, response} =
               GoogleAd.get("https://example.com/ad", responder: custom_responder)

      assert response.status == :ok
    end
  end
end
