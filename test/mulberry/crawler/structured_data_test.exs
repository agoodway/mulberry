defmodule Mulberry.Crawler.StructuredDataTest do
  use ExUnit.Case, async: true

  alias Mulberry.Crawler.StructuredData

  describe "extract_all/1" do
    test "extracts all structured data types from HTML" do
      html = """
      <html>
      <head>
        <meta property="og:title" content="Test Page">
        <meta name="twitter:card" content="summary">
        <script type="application/ld+json">{"@type": "Article"}</script>
      </head>
      </html>
      """

      result = StructuredData.extract_all(html)

      assert result.json_ld == [%{"@type" => "Article"}]
      assert result.open_graph == %{title: "Test Page"}
      assert result.twitter_card == %{card: "summary"}
    end

    test "returns empty/nil values for missing data" do
      html = "<html><head><title>Plain Page</title></head></html>"

      result = StructuredData.extract_all(html)

      assert result.json_ld == []
      assert result.open_graph == nil
      assert result.twitter_card == nil
    end

    test "handles non-string input" do
      assert StructuredData.extract_all(nil) == %{
               json_ld: [],
               open_graph: nil,
               twitter_card: nil
             }

      assert StructuredData.extract_all(123) == %{
               json_ld: [],
               open_graph: nil,
               twitter_card: nil
             }
    end
  end

  describe "extract_json_ld/1" do
    test "extracts single JSON-LD object" do
      html = """
      <html>
      <head>
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "Organization",
          "name": "Test Company"
        }
        </script>
      </head>
      </html>
      """

      result = StructuredData.extract_json_ld(html)

      assert length(result) == 1
      assert hd(result)["@type"] == "Organization"
      assert hd(result)["name"] == "Test Company"
    end

    test "extracts multiple JSON-LD objects" do
      html = """
      <html>
      <head>
        <script type="application/ld+json">{"@type": "Article"}</script>
        <script type="application/ld+json">{"@type": "WebPage"}</script>
      </head>
      </html>
      """

      result = StructuredData.extract_json_ld(html)

      assert length(result) == 2
      types = Enum.map(result, & &1["@type"])
      assert "Article" in types
      assert "WebPage" in types
    end

    test "handles JSON-LD array" do
      html = """
      <script type="application/ld+json">
      [
        {"@type": "BreadcrumbList"},
        {"@type": "Product"}
      ]
      </script>
      """

      result = StructuredData.extract_json_ld(html)

      assert length(result) == 2
    end

    test "skips invalid JSON" do
      html = """
      <script type="application/ld+json">
      {invalid json here}
      </script>
      <script type="application/ld+json">
      {"@type": "Valid"}
      </script>
      """

      result = StructuredData.extract_json_ld(html)

      assert length(result) == 1
      assert hd(result)["@type"] == "Valid"
    end

    test "returns empty list for no JSON-LD" do
      html = "<html><head></head></html>"

      assert StructuredData.extract_json_ld(html) == []
    end

    test "ignores other script types" do
      html = """
      <script type="text/javascript">var x = 1;</script>
      <script type="application/ld+json">{"@type": "Test"}</script>
      """

      result = StructuredData.extract_json_ld(html)

      assert length(result) == 1
      assert hd(result)["@type"] == "Test"
    end

    test "handles non-string input" do
      assert StructuredData.extract_json_ld(nil) == []
      assert StructuredData.extract_json_ld(123) == []
    end
  end

  describe "extract_open_graph/1" do
    test "extracts basic Open Graph properties" do
      html = """
      <html>
      <head>
        <meta property="og:title" content="My Page Title">
        <meta property="og:description" content="Page description">
        <meta property="og:image" content="https://example.com/image.jpg">
        <meta property="og:url" content="https://example.com/page">
        <meta property="og:type" content="article">
      </head>
      </html>
      """

      result = StructuredData.extract_open_graph(html)

      assert result.title == "My Page Title"
      assert result.description == "Page description"
      assert result.image == "https://example.com/image.jpg"
      assert result.url == "https://example.com/page"
      assert result.type == "article"
    end

    test "extracts site_name and locale" do
      html = """
      <meta property="og:site_name" content="My Website">
      <meta property="og:locale" content="en_US">
      """

      result = StructuredData.extract_open_graph(html)

      assert result.site_name == "My Website"
      assert result.locale == "en_US"
    end

    test "returns nil when no Open Graph tags found" do
      html = """
      <html>
      <head>
        <meta name="description" content="Regular description">
      </head>
      </html>
      """

      assert StructuredData.extract_open_graph(html) == nil
    end

    test "handles meta tags without content" do
      html = """
      <meta property="og:title">
      <meta property="og:description" content="Has content">
      """

      result = StructuredData.extract_open_graph(html)

      assert result == %{description: "Has content"}
    end

    test "handles non-string input" do
      assert StructuredData.extract_open_graph(nil) == nil
      assert StructuredData.extract_open_graph(123) == nil
    end
  end

  describe "extract_twitter_card/1" do
    test "extracts Twitter Card properties with name attribute" do
      html = """
      <html>
      <head>
        <meta name="twitter:card" content="summary_large_image">
        <meta name="twitter:title" content="Tweet Title">
        <meta name="twitter:description" content="Tweet description">
        <meta name="twitter:image" content="https://example.com/twitter.jpg">
        <meta name="twitter:site" content="@mysite">
        <meta name="twitter:creator" content="@author">
      </head>
      </html>
      """

      result = StructuredData.extract_twitter_card(html)

      assert result.card == "summary_large_image"
      assert result.title == "Tweet Title"
      assert result.description == "Tweet description"
      assert result.image == "https://example.com/twitter.jpg"
      assert result.site == "@mysite"
      assert result.creator == "@author"
    end

    test "extracts Twitter Card properties with property attribute" do
      html = """
      <meta property="twitter:card" content="summary">
      <meta property="twitter:title" content="Property Title">
      """

      result = StructuredData.extract_twitter_card(html)

      assert result.card == "summary"
      assert result.title == "Property Title"
    end

    test "handles mixed name and property attributes" do
      html = """
      <meta name="twitter:card" content="summary">
      <meta property="twitter:title" content="Mixed Title">
      """

      result = StructuredData.extract_twitter_card(html)

      assert result.card == "summary"
      assert result.title == "Mixed Title"
    end

    test "returns nil when no Twitter Card tags found" do
      html = """
      <html>
      <head>
        <meta property="og:title" content="OG only">
      </head>
      </html>
      """

      assert StructuredData.extract_twitter_card(html) == nil
    end

    test "handles non-string input" do
      assert StructuredData.extract_twitter_card(nil) == nil
      assert StructuredData.extract_twitter_card(123) == nil
    end
  end

  describe "real-world examples" do
    test "handles typical article page" do
      html = """
      <!DOCTYPE html>
      <html>
      <head>
        <title>Breaking News Article</title>
        <meta property="og:title" content="Breaking News Article">
        <meta property="og:description" content="Important news story">
        <meta property="og:image" content="https://news.com/article.jpg">
        <meta property="og:type" content="article">
        <meta name="twitter:card" content="summary_large_image">
        <meta name="twitter:title" content="Breaking News Article">
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "NewsArticle",
          "headline": "Breaking News Article",
          "datePublished": "2024-01-15"
        }
        </script>
      </head>
      <body></body>
      </html>
      """

      result = StructuredData.extract_all(html)

      # JSON-LD
      assert length(result.json_ld) == 1
      assert hd(result.json_ld)["@type"] == "NewsArticle"
      assert hd(result.json_ld)["headline"] == "Breaking News Article"

      # Open Graph
      assert result.open_graph.title == "Breaking News Article"
      assert result.open_graph.type == "article"

      # Twitter Card
      assert result.twitter_card.card == "summary_large_image"
    end

    test "handles e-commerce product page" do
      html = """
      <html>
      <head>
        <meta property="og:title" content="Amazing Product">
        <meta property="og:type" content="product">
        <meta property="og:image" content="https://shop.com/product.jpg">
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "Product",
          "name": "Amazing Product",
          "offers": {
            "@type": "Offer",
            "price": "99.99",
            "priceCurrency": "USD"
          }
        }
        </script>
      </head>
      </html>
      """

      result = StructuredData.extract_all(html)

      # JSON-LD with nested structure
      product = hd(result.json_ld)
      assert product["@type"] == "Product"
      assert product["offers"]["price"] == "99.99"

      # Open Graph
      assert result.open_graph.type == "product"
    end

    test "handles malformed HTML gracefully" do
      html = """
      <html>
      <head>
        <meta property="og:title" content="Incomplete
        <script type="application/ld+json">{"@type": "Test"}</script>
      </head>
      """

      # Should not raise, may extract partial data
      result = StructuredData.extract_all(html)

      assert is_list(result.json_ld)
      # The OG tag is malformed, may or may not be extracted
    end
  end
end
