defmodule Mulberry.Document.GoogleAdTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Mulberry.Document.GoogleAd
  alias Mulberry.Retriever.GoogleAd, as: GoogleAdRetriever

  describe "new/1" do
    test "creates a GoogleAd struct with attributes" do
      attrs = %{
        advertiser_id: "AR01614014350098432001",
        creative_id: "CR10449491775734153217",
        format: "text",
        ad_url: "https://adstransparency.google.com/advertiser/AR01614014350098432001/creative/CR10449491775734153217",
        advertiser_name: "Lululemon Athletica Canada Inc.",
        domain: "lululemon.com",
        first_shown: "2023-12-29T21:59:16.000Z",
        last_shown: "2025-03-28T01:46:12.000Z"
      }

      ad = GoogleAd.new(attrs)

      assert %GoogleAd{} = ad
      assert ad.advertiser_id == "AR01614014350098432001"
      assert ad.creative_id == "CR10449491775734153217"
      assert ad.format == "text"
      assert ad.advertiser_name == "Lululemon Athletica Canada Inc."
      assert ad.domain == "lululemon.com"
    end
  end

  describe "Mulberry.Document implementation" do
    setup do
      ad = GoogleAd.new(%{
        advertiser_id: "AR01614014350098432001",
        creative_id: "CR10449491775734153217",
        format: "text",
        ad_url: "https://adstransparency.google.com/advertiser/AR01614014350098432001/creative/CR10449491775734153217",
        advertiser_name: "Lululemon Athletica Canada Inc.",
        domain: "lululemon.com",
        first_shown: "2023-12-29T21:59:16.000Z",
        last_shown: "2025-03-28T01:46:12.000Z"
      })

      {:ok, ad: ad}
    end

    test "load/2 fetches additional details when ad_url is present", %{ad: ad} do
      detailed_data = %{
        "overallImpressions" => %{"min" => 1000, "max" => 5000},
        "creativeRegions" => [%{"regionCode" => "US", "regionName" => "United States"}],
        "regionStats" => [],
        "variations" => [
          %{
            "headline" => "Best Yoga Pants",
            "description" => "Shop our collection",
            "destinationUrl" => "lululemon.com/yoga"
          }
        ]
      }

      expect(GoogleAdRetriever, :get, fn _url, _opts ->
        {:ok, %Mulberry.Retriever.Response{status: :ok, content: detailed_data}}
      end)

      assert {:ok, loaded_ad} = Mulberry.Document.load(ad)
      assert loaded_ad.overall_impressions == %{"min" => 1000, "max" => 5000}
      assert length(loaded_ad.creative_regions) == 1
      assert length(loaded_ad.variations) == 1
    end

    test "load/2 returns original ad when retriever fails", %{ad: ad} do
      expect(GoogleAdRetriever, :get, fn _url, _opts ->
        {:error, :network_error}
      end)

      assert {:ok, loaded_ad} = Mulberry.Document.load(ad)
      assert loaded_ad == ad
    end

    test "load/2 returns original ad when no ad_url", %{ad: ad} do
      ad_without_url = %{ad | ad_url: nil}
      assert {:ok, loaded_ad} = Mulberry.Document.load(ad_without_url)
      assert loaded_ad == ad_without_url
    end

    test "generate_summary/2", %{ad: ad} do
      expect(Mulberry.Text, :summarize, fn text, _opts ->
        assert text =~ "Lululemon Athletica Canada Inc."
        assert text =~ "lululemon.com"
        {:ok, "Summary of the ad"}
      end)

      assert {:ok, ad_with_summary} = Mulberry.Document.generate_summary(ad)
      assert ad_with_summary.summary == "Summary of the ad"
    end

    test "generate_keywords/2", %{ad: ad} do
      ad_with_variations = %{ad | 
        variations: [
          %{"headline" => "Best Yoga Pants - Premium Quality"},
          %{"headline" => "Comfortable Athletic Wear"}
        ],
        creative_regions: [
          %{"regionName" => "United States"},
          %{"regionName" => "Canada"}
        ]
      }

      assert {:ok, ad_with_keywords} = Mulberry.Document.generate_keywords(ad_with_variations)
      assert "text" in ad_with_keywords.keywords
      assert "United States" in ad_with_keywords.keywords
      assert "Canada" in ad_with_keywords.keywords
      # Keywords from variations
      assert Enum.any?(ad_with_keywords.keywords, &(&1 =~ "Yoga"))
    end

    test "generate_title/2", %{ad: ad} do
      assert {:ok, ad_with_title} = Mulberry.Document.generate_title(ad)
      assert ad_with_title == ad
    end

    test "to_text/2", %{ad: ad} do
      assert {:ok, text} = Mulberry.Document.to_text(ad)
      assert text =~ "Google Ad"
      assert text =~ "Creative ID: CR10449491775734153217"
      assert text =~ "Advertiser: Lululemon Athletica Canada Inc."
      assert text =~ "Domain: lululemon.com"
      assert text =~ "First shown: 2023-12-29T21:59:16.000Z"
      assert text =~ "Last shown: 2025-03-28T01:46:12.000Z"
    end

    test "to_text/2 with detailed data", %{ad: ad} do
      detailed_ad = %{ad |
        overall_impressions: %{"min" => 1000, "max" => 5000},
        creative_regions: [%{"regionName" => "United States"}],
        variations: [
          %{
            "headline" => "Best Yoga Pants",
            "description" => "Shop our collection",
            "destinationUrl" => "lululemon.com/yoga"
          }
        ]
      }

      assert {:ok, text} = Mulberry.Document.to_text(detailed_ad)
      assert text =~ "Overall Impressions: 1000 - 5000"
      assert text =~ "Regions: United States"
      assert text =~ "Ad Variations:"
      assert text =~ "Headline: Best Yoga Pants"
      assert text =~ "Description: Shop our collection"
      assert text =~ "Destination: lululemon.com/yoga"
    end

    test "to_tokens/2", %{ad: ad} do
      expect(Mulberry.Text, :tokens, fn _text ->
        {:ok, ["token1", "token2", "token3"]}
      end)

      assert {:ok, tokens} = Mulberry.Document.to_tokens(ad)
      assert tokens == ["token1", "token2", "token3"]
    end

    test "to_chunks/2", %{ad: ad} do
      chunk = %TextChunker.Chunk{text: "chunk content"}
      
      expect(Mulberry.Text, :split, fn _text ->
        [chunk]
      end)

      assert {:ok, chunks} = Mulberry.Document.to_chunks(ad)
      assert chunks == [chunk]
    end
  end
end