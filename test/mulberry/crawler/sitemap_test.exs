defmodule Mulberry.Crawler.SitemapTest do
  use ExUnit.Case, async: true

  alias Mulberry.Crawler.Sitemap

  describe "parse_sitemap_xml/1" do
    test "parses basic urlset sitemap" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <url>
          <loc>https://example.com/page1</loc>
          <lastmod>2024-01-15</lastmod>
          <changefreq>weekly</changefreq>
          <priority>0.8</priority>
        </url>
        <url>
          <loc>https://example.com/page2</loc>
        </url>
      </urlset>
      """

      {:ok, :urlset, entries} = Sitemap.parse_sitemap_xml(xml)

      assert length(entries) == 2

      first = Enum.find(entries, &(&1.loc == "https://example.com/page1"))
      assert first.lastmod == "2024-01-15"
      assert first.changefreq == "weekly"
      assert first.priority == 0.8

      second = Enum.find(entries, &(&1.loc == "https://example.com/page2"))
      assert second.lastmod == nil
      assert second.changefreq == nil
      assert second.priority == nil
    end

    test "parses sitemap index" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <sitemap>
          <loc>https://example.com/sitemap1.xml</loc>
          <lastmod>2024-01-15</lastmod>
        </sitemap>
        <sitemap>
          <loc>https://example.com/sitemap2.xml</loc>
        </sitemap>
      </sitemapindex>
      """

      {:ok, :sitemapindex, entries} = Sitemap.parse_sitemap_xml(xml)

      assert length(entries) == 2

      first = Enum.find(entries, &(&1.loc == "https://example.com/sitemap1.xml"))
      assert first.lastmod == "2024-01-15"

      second = Enum.find(entries, &(&1.loc == "https://example.com/sitemap2.xml"))
      assert second.lastmod == nil
    end

    test "skips entries without loc" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <url>
          <loc>https://example.com/valid</loc>
        </url>
        <url>
          <lastmod>2024-01-15</lastmod>
        </url>
      </urlset>
      """

      {:ok, :urlset, entries} = Sitemap.parse_sitemap_xml(xml)

      assert length(entries) == 1
      assert hd(entries).loc == "https://example.com/valid"
    end

    test "handles empty urlset" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      </urlset>
      """

      {:ok, :urlset, entries} = Sitemap.parse_sitemap_xml(xml)

      assert entries == []
    end

    test "handles empty sitemap index" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      </sitemapindex>
      """

      {:ok, :sitemapindex, entries} = Sitemap.parse_sitemap_xml(xml)

      assert entries == []
    end

    test "returns error for unknown format" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <other>something</other>
      """

      assert {:error, :unknown_sitemap_format} = Sitemap.parse_sitemap_xml(xml)
    end

    test "returns error for content without sitemap elements" do
      xml = "not valid xml <unclosed"

      # Floki is forgiving with malformed HTML/XML, so it parses but doesn't find sitemap elements
      assert {:error, :unknown_sitemap_format} = Sitemap.parse_sitemap_xml(xml)
    end

    test "handles non-string input" do
      assert {:error, :invalid_content} = Sitemap.parse_sitemap_xml(nil)
      assert {:error, :invalid_content} = Sitemap.parse_sitemap_xml(123)
    end

    test "parses priority as float" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <url>
          <loc>https://example.com/high</loc>
          <priority>1.0</priority>
        </url>
        <url>
          <loc>https://example.com/low</loc>
          <priority>0.1</priority>
        </url>
        <url>
          <loc>https://example.com/invalid</loc>
          <priority>invalid</priority>
        </url>
      </urlset>
      """

      {:ok, :urlset, entries} = Sitemap.parse_sitemap_xml(xml)

      high = Enum.find(entries, &(&1.loc == "https://example.com/high"))
      assert high.priority == 1.0

      low = Enum.find(entries, &(&1.loc == "https://example.com/low"))
      assert low.priority == 0.1

      invalid = Enum.find(entries, &(&1.loc == "https://example.com/invalid"))
      assert invalid.priority == nil
    end

    test "handles whitespace in URLs" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <url>
          <loc>
            https://example.com/page
          </loc>
        </url>
      </urlset>
      """

      {:ok, :urlset, entries} = Sitemap.parse_sitemap_xml(xml)

      assert length(entries) == 1
      assert hd(entries).loc == "https://example.com/page"
    end
  end

  describe "parse_sitemap_xml/1 with complex real-world sitemaps" do
    test "handles sitemap with namespaces" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
              xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">
        <url>
          <loc>https://example.com/page</loc>
          <image:image>
            <image:loc>https://example.com/image.jpg</image:loc>
          </image:image>
        </url>
      </urlset>
      """

      {:ok, :urlset, entries} = Sitemap.parse_sitemap_xml(xml)

      assert length(entries) == 1
      assert hd(entries).loc == "https://example.com/page"
    end

    test "handles news sitemap format" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
              xmlns:news="http://www.google.com/schemas/sitemap-news/0.9">
        <url>
          <loc>https://example.com/news/article</loc>
          <news:news>
            <news:publication>
              <news:name>Example News</news:name>
              <news:language>en</news:language>
            </news:publication>
            <news:title>Breaking News</news:title>
          </news:news>
        </url>
      </urlset>
      """

      {:ok, :urlset, entries} = Sitemap.parse_sitemap_xml(xml)

      assert length(entries) == 1
      assert hd(entries).loc == "https://example.com/news/article"
    end
  end
end
