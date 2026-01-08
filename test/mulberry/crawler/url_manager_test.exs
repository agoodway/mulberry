defmodule Mulberry.Crawler.URLManagerTest do
  use ExUnit.Case, async: true

  alias Mulberry.Crawler.URLManager

  describe "compile_patterns/1" do
    test "compiles valid regex patterns" do
      {:ok, patterns} = URLManager.compile_patterns(["/blog/", "\\.pdf$", ".*\\.jpg$"])

      assert length(patterns) == 3
      assert Enum.all?(patterns, &is_struct(&1, Regex))
    end

    test "returns error for invalid regex pattern" do
      {:error, {:invalid_pattern, pattern, _reason}} = URLManager.compile_patterns(["[invalid"])

      assert pattern == "[invalid"
    end

    test "returns empty list for empty input" do
      assert {:ok, []} = URLManager.compile_patterns([])
    end

    test "returns empty list for non-list input" do
      assert {:ok, []} = URLManager.compile_patterns(nil)
      assert {:ok, []} = URLManager.compile_patterns("string")
    end

    test "stops at first invalid pattern" do
      {:error, {:invalid_pattern, pattern, _}} =
        URLManager.compile_patterns(["/valid/", "[invalid", "/also-valid/"])

      assert pattern == "[invalid"
    end
  end

  describe "matches_patterns?/2" do
    test "returns true when URL matches any pattern" do
      {:ok, patterns} = URLManager.compile_patterns(["/blog/", "/news/"])

      assert URLManager.matches_patterns?("http://example.com/blog/post", patterns)
      assert URLManager.matches_patterns?("http://example.com/news/article", patterns)
    end

    test "returns false when URL doesn't match any pattern" do
      {:ok, patterns} = URLManager.compile_patterns(["/blog/", "/news/"])

      refute URLManager.matches_patterns?("http://example.com/about", patterns)
    end

    test "returns false for empty pattern list" do
      refute URLManager.matches_patterns?("http://example.com/anything", [])
    end

    test "supports regex special characters" do
      {:ok, patterns} = URLManager.compile_patterns(["\\.pdf$"])

      assert URLManager.matches_patterns?("http://example.com/doc.pdf", patterns)
      refute URLManager.matches_patterns?("http://example.com/pdf/page", patterns)
    end

    test "supports start and end anchors" do
      {:ok, patterns} = URLManager.compile_patterns(["^https://secure"])

      assert URLManager.matches_patterns?("https://secure.example.com/page", patterns)
      refute URLManager.matches_patterns?("http://example.com/https://secure", patterns)
    end
  end

  describe "filter_urls_by_patterns/2" do
    test "filters by include patterns" do
      {:ok, include} = URLManager.compile_patterns(["/blog/"])

      urls = [
        "http://site.com/blog/post",
        "http://site.com/about",
        "http://site.com/blog/another"
      ]

      result = URLManager.filter_urls_by_patterns(urls, include_patterns: include)

      assert result == ["http://site.com/blog/post", "http://site.com/blog/another"]
    end

    test "filters by exclude patterns" do
      {:ok, exclude} = URLManager.compile_patterns(["/admin/", "/private/"])

      urls = [
        "http://site.com/page",
        "http://site.com/admin/dashboard",
        "http://site.com/private/data",
        "http://site.com/public"
      ]

      result = URLManager.filter_urls_by_patterns(urls, exclude_patterns: exclude)

      assert result == ["http://site.com/page", "http://site.com/public"]
    end

    test "combines include and exclude patterns" do
      {:ok, include} = URLManager.compile_patterns(["/blog/"])
      {:ok, exclude} = URLManager.compile_patterns(["/draft/"])

      urls = [
        "http://site.com/blog/post",
        "http://site.com/blog/draft/1",
        "http://site.com/about",
        "http://site.com/blog/published"
      ]

      result =
        URLManager.filter_urls_by_patterns(urls,
          include_patterns: include,
          exclude_patterns: exclude
        )

      assert result == ["http://site.com/blog/post", "http://site.com/blog/published"]
    end

    test "empty include patterns allow all URLs" do
      {:ok, exclude} = URLManager.compile_patterns(["/admin/"])

      urls = ["http://site.com/page", "http://site.com/admin/"]

      result = URLManager.filter_urls_by_patterns(urls, exclude_patterns: exclude)

      assert result == ["http://site.com/page"]
    end

    test "empty exclude patterns don't filter any URLs" do
      {:ok, include} = URLManager.compile_patterns(["/blog/"])

      urls = ["http://site.com/blog/post", "http://site.com/blog/admin/"]

      result = URLManager.filter_urls_by_patterns(urls, include_patterns: include)

      assert result == ["http://site.com/blog/post", "http://site.com/blog/admin/"]
    end

    test "returns all URLs when no patterns specified" do
      urls = ["http://site.com/a", "http://site.com/b"]

      result = URLManager.filter_urls_by_patterns(urls)

      assert result == urls
    end

    test "handles file extension patterns" do
      {:ok, exclude} = URLManager.compile_patterns(["\\.pdf$", "\\.jpg$", "\\.png$"])

      urls = [
        "http://site.com/page",
        "http://site.com/doc.pdf",
        "http://site.com/image.jpg",
        "http://site.com/photo.png",
        "http://site.com/article"
      ]

      result = URLManager.filter_urls_by_patterns(urls, exclude_patterns: exclude)

      assert result == ["http://site.com/page", "http://site.com/article"]
    end
  end

  describe "normalize_url/1" do
    test "normalizes scheme to lowercase" do
      {:ok, url} = URLManager.normalize_url("HTTP://example.com/path")
      assert url == "http://example.com/path"
    end

    test "normalizes host to lowercase" do
      {:ok, url} = URLManager.normalize_url("http://EXAMPLE.COM/path")
      assert url == "http://example.com/path"
    end

    test "removes default ports" do
      {:ok, url1} = URLManager.normalize_url("http://example.com:80/path")
      {:ok, url2} = URLManager.normalize_url("https://example.com:443/path")

      assert url1 == "http://example.com/path"
      assert url2 == "https://example.com/path"
    end

    test "preserves non-default ports" do
      {:ok, url} = URLManager.normalize_url("http://example.com:8080/path")
      assert url == "http://example.com:8080/path"
    end

    test "sorts query parameters" do
      {:ok, url} = URLManager.normalize_url("http://example.com?b=2&a=1")
      assert url == "http://example.com/?a=1&b=2"
    end

    test "removes fragments" do
      {:ok, url} = URLManager.normalize_url("http://example.com/path#section")
      assert url == "http://example.com/path"
    end

    test "returns error for invalid URL" do
      assert {:error, :invalid_url} = URLManager.normalize_url("not a url")
      assert {:error, :invalid_url} = URLManager.normalize_url("/relative/path")
    end
  end

  describe "same_domain?/2" do
    test "returns true for exact match" do
      assert URLManager.same_domain?("http://example.com/page", "example.com")
    end

    test "returns true for subdomain match" do
      assert URLManager.same_domain?("http://www.example.com/page", "example.com")
      assert URLManager.same_domain?("http://blog.example.com/page", "example.com")
    end

    test "returns false for different domain" do
      refute URLManager.same_domain?("http://other.com/page", "example.com")
    end

    test "handles case insensitivity" do
      assert URLManager.same_domain?("http://EXAMPLE.COM/page", "example.com")
      assert URLManager.same_domain?("http://example.com/page", "EXAMPLE.COM")
    end
  end

  describe "resolve_url/2" do
    test "resolves absolute path" do
      {:ok, url} = URLManager.resolve_url("/path", "http://example.com/other")
      assert url == "http://example.com/path"
    end

    test "returns absolute URL unchanged" do
      {:ok, url} = URLManager.resolve_url("http://other.com/path", "http://example.com")
      assert url == "http://other.com/path"
    end

    test "resolves relative path" do
      {:ok, url} = URLManager.resolve_url("subpage", "http://example.com/dir/page")
      assert url == "http://example.com/dir/subpage"
    end
  end

  describe "extract_domain/1" do
    test "extracts domain from URL" do
      {:ok, domain} = URLManager.extract_domain("http://www.example.com/path")
      assert domain == "www.example.com"
    end

    test "returns error for invalid URL" do
      assert {:error, :invalid_url} = URLManager.extract_domain("not a url")
    end
  end
end
