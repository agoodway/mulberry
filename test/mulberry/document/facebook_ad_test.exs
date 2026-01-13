defmodule Mulberry.Document.FacebookAdTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Mulberry.Document.FacebookAd
  alias Mulberry.Document
  alias Mulberry.Text

  describe "new/1" do
    test "creates a new FacebookAd struct" do
      attrs = %{
        ad_archive_id: "123",
        page_name: "Test Company",
        body_text: "Buy our products!",
        is_active: true
      }

      ad = FacebookAd.new(attrs)

      assert ad.__struct__ == FacebookAd
      assert ad.ad_archive_id == "123"
      assert ad.page_name == "Test Company"
      assert ad.body_text == "Buy our products!"
      assert ad.is_active == true
    end
  end

  describe "Document.load/2" do
    test "returns the ad unchanged (pre-loaded from API)" do
      ad = FacebookAd.new(%{ad_archive_id: "123", page_name: "Test"})
      assert {:ok, ^ad} = Document.load(ad, [])
    end
  end

  describe "Document.generate_summary/2" do
    test "generates summary from ad content" do
      ad =
        FacebookAd.new(%{
          page_name: "Nike",
          title: "Just Do It",
          body_text: "Discover our latest collection of running shoes.",
          link_description: "Shop the newest Nike running shoes",
          cta_text: "Shop Now"
        })

      expect(Text, :summarize, fn content, _opts ->
        assert content =~ "Advertiser: Nike"
        assert content =~ "Title: Just Do It"
        assert content =~ "Content: Discover our latest collection"
        assert content =~ "Description: Shop the newest Nike"
        assert content =~ "Call to Action: Shop Now"
        {:ok, "Nike ad for running shoes with Shop Now CTA"}
      end)

      {:ok, ad_with_summary} = Document.generate_summary(ad, [])
      assert ad_with_summary.summary == "Nike ad for running shoes with Shop Now CTA"
    end

    test "handles ads with minimal content" do
      ad = FacebookAd.new(%{page_name: "Simple Ad"})

      expect(Text, :summarize, fn content, _opts ->
        assert content == "Advertiser: Simple Ad"
        {:ok, "Simple ad summary"}
      end)

      {:ok, ad_with_summary} = Document.generate_summary(ad, [])
      assert ad_with_summary.summary == "Simple ad summary"
    end

    test "returns error when summarization fails" do
      ad = FacebookAd.new(%{page_name: "Test"})

      expect(Text, :summarize, fn _content, _opts ->
        {:error, "API error"}
      end)

      assert {:error, "API error", ^ad} = Document.generate_summary(ad, [])
    end
  end

  describe "Document.generate_keywords/2" do
    test "returns empty keywords for now" do
      ad = FacebookAd.new(%{page_name: "Test"})
      {:ok, ad_with_keywords} = Document.generate_keywords(ad, [])
      assert ad_with_keywords.keywords == []
    end
  end

  describe "Document.generate_title/2" do
    test "keeps existing title" do
      ad = FacebookAd.new(%{title: "Existing Title"})
      {:ok, result} = Document.generate_title(ad, [])
      assert result.title == "Existing Title"
    end

    test "generates title from page name and body text" do
      ad =
        FacebookAd.new(%{
          page_name: "Apple",
          body_text: "Introducing the new iPhone. Experience innovation like never before."
        })

      {:ok, result} = Document.generate_title(ad, [])
      assert result.title == "Apple: Introducing the new iPhone"
    end

    test "generates title from page name only" do
      ad = FacebookAd.new(%{page_name: "Microsoft"})
      {:ok, result} = Document.generate_title(ad, [])
      assert result.title == "Ad by Microsoft"
    end

    test "generates generic title when no content" do
      ad = FacebookAd.new(%{})
      {:ok, result} = Document.generate_title(ad, [])
      assert result.title == "Facebook Ad"
    end
  end

  describe "Document.to_text/2" do
    test "converts ad to text representation" do
      ad =
        FacebookAd.new(%{
          page_name: "Tesla",
          title: "Model S Plaid",
          body_text: "The quickest accelerating car in the world.",
          link_description: "Learn more about Model S",
          cta_text: "Order Now",
          cta_type: "SHOP_NOW",
          link_url: "https://tesla.com/models",
          publisher_platform: ["FACEBOOK", "INSTAGRAM"],
          is_active: true,
          impressions_text: "10K-50K",
          targeted_or_reached_countries: ["US", "CA"]
        })

      {:ok, text} = Document.to_text(ad, [])

      assert text =~ "=== Facebook Ad ==="
      assert text =~ "Advertiser: Tesla"
      assert text =~ "Title: Model S Plaid"
      assert text =~ "The quickest accelerating car in the world"
      assert text =~ "Description: Learn more about Model S"
      assert text =~ "Call to Action: Order Now (SHOP_NOW)"
      assert text =~ "Link: https://tesla.com/models"
      assert text =~ "Platforms: FACEBOOK, INSTAGRAM"
      assert text =~ "Status: Active"
      assert text =~ "Impressions: 10K-50K"
      assert text =~ "Countries: US, CA"
    end

    test "handles minimal ad data" do
      ad = FacebookAd.new(%{is_active: false})
      {:ok, text} = Document.to_text(ad, [])

      assert text =~ "=== Facebook Ad ==="
      assert text =~ "Platforms: Unknown"
      assert text =~ "Status: Inactive"
    end
  end

  describe "Document.to_tokens/2" do
    test "tokenizes ad text" do
      ad =
        FacebookAd.new(%{
          page_name: "Nike",
          body_text: "Just do it"
        })

      expect(Text, :tokens, fn text ->
        assert text =~ "Nike"
        assert text =~ "Just do it"
        {:ok, ["Nike", "Just", "do", "it"]}
      end)

      {:ok, tokens} = Document.to_tokens(ad, [])
      assert tokens == ["Nike", "Just", "do", "it"]
    end

    test "returns error when tokenization fails" do
      ad = FacebookAd.new(%{page_name: "Test"})

      expect(Text, :tokens, fn _text ->
        {:error, "Tokenization error"}
      end)

      assert {:error, :tokenization_failed} = Document.to_tokens(ad, [])
    end
  end

  describe "Document.to_chunks/2" do
    test "chunks ad text" do
      ad =
        FacebookAd.new(%{
          page_name: "Long Ad Company",
          body_text: String.duplicate("This is a long ad text. ", 100)
        })

      expect(Text, :split, fn text ->
        assert text =~ "Long Ad Company"
        assert text =~ "This is a long ad text"
        [%{text: "chunk1"}, %{text: "chunk2"}]
      end)

      {:ok, chunks} = Document.to_chunks(ad, [])
      assert length(chunks) == 2
    end
  end
end
