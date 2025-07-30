defmodule Mulberry.Crawler.URLManager do
  @moduledoc """
  Manages URL normalization, deduplication, and filtering for the crawler.

  This module provides utilities for:
  - Normalizing URLs to a canonical form
  - Tracking visited URLs to avoid duplicates
  - Filtering URLs based on domain and path patterns
  - Resolving relative URLs to absolute URLs
  """

  @type url :: String.t()

  @doc """
  Normalizes a URL to its canonical form.

  This includes:
  - Lowercasing the scheme and host
  - Removing default ports (80 for http, 443 for https)
  - Removing trailing slashes from paths
  - Sorting query parameters
  - Removing fragments

  ## Examples

      iex> Mulberry.Crawler.URLManager.normalize_url("HTTP://EXAMPLE.COM:80/path/?b=2&a=1#fragment")
      {:ok, "http://example.com/path?a=1&b=2"}

      iex> Mulberry.Crawler.URLManager.normalize_url("not a url")
      {:error, :invalid_url}
  """
  @spec normalize_url(url()) :: {:ok, url()} | {:error, :invalid_url}
  def normalize_url(url) do
    case URI.parse(url) do
      %URI{scheme: nil} ->
        {:error, :invalid_url}

      %URI{host: nil} ->
        {:error, :invalid_url}

      uri ->
        normalized =
          uri
          |> normalize_scheme()
          |> normalize_host()
          |> normalize_port()
          |> normalize_path()
          |> normalize_query()
          |> remove_fragment()
          |> URI.to_string()

        {:ok, normalized}
    end
  rescue
    _ -> {:error, :invalid_url}
  end

  @doc """
  Checks if a URL matches the given domain.

  ## Examples

      iex> Mulberry.Crawler.URLManager.same_domain?("http://example.com/page", "example.com")
      true

      iex> Mulberry.Crawler.URLManager.same_domain?("http://sub.example.com/page", "example.com")
      true

      iex> Mulberry.Crawler.URLManager.same_domain?("http://other.com/page", "example.com")
      false
  """
  @spec same_domain?(url(), String.t()) :: boolean()
  def same_domain?(url, domain) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        normalized_host = String.downcase(host)
        normalized_domain = String.downcase(domain)

        normalized_host == normalized_domain ||
          String.ends_with?(normalized_host, "." <> normalized_domain)

      _ ->
        false
    end
  end

  @doc """
  Resolves a potentially relative URL against a base URL.

  ## Examples

      iex> Mulberry.Crawler.URLManager.resolve_url("/path", "http://example.com/other")
      {:ok, "http://example.com/path"}

      iex> Mulberry.Crawler.URLManager.resolve_url("http://example.com/absolute", "http://base.com")
      {:ok, "http://example.com/absolute"}

      iex> Mulberry.Crawler.URLManager.resolve_url("relative/path", "http://example.com/dir/page.html")
      {:ok, "http://example.com/dir/relative/path"}
  """
  @spec resolve_url(url(), url()) :: {:ok, url()} | {:error, :invalid_url}
  def resolve_url(url, base_url) do
    case {URI.parse(url), URI.parse(base_url)} do
      {%URI{scheme: nil, host: nil} = relative_uri, base_uri} ->
        resolved = URI.merge(base_uri, relative_uri) |> URI.to_string()
        {:ok, resolved}

      {%URI{scheme: scheme} = absolute_uri, _} when scheme in ["http", "https"] ->
        {:ok, URI.to_string(absolute_uri)}

      _ ->
        {:error, :invalid_url}
    end
  rescue
    _ -> {:error, :invalid_url}
  end

  @doc """
  Filters a list of URLs based on allowed domains and patterns.

  ## Options
    - `:allowed_domains` - List of domains to allow (supports subdomains)
    - `:blocked_paths` - List of path patterns to block (uses String.contains?)
    - `:allowed_paths` - List of path patterns to allow (uses String.contains?)

  ## Examples

      iex> urls = ["http://example.com/page", "http://other.com/page", "http://example.com/admin"]
      iex> Mulberry.Crawler.URLManager.filter_urls(urls, allowed_domains: ["example.com"], blocked_paths: ["/admin"])
      ["http://example.com/page"]
  """
  @spec filter_urls([url()], keyword()) :: [url()]
  def filter_urls(urls, opts \\ []) do
    allowed_domains = Keyword.get(opts, :allowed_domains, [])
    blocked_paths = Keyword.get(opts, :blocked_paths, [])
    allowed_paths = Keyword.get(opts, :allowed_paths, [])

    Enum.filter(urls, fn url ->
      passes_domain_filter?(url, allowed_domains) &&
        passes_path_filter?(url, allowed_paths, blocked_paths)
    end)
  end

  @doc """
  Extracts the domain from a URL.

  ## Examples

      iex> Mulberry.Crawler.URLManager.extract_domain("http://www.example.com/path")
      {:ok, "www.example.com"}

      iex> Mulberry.Crawler.URLManager.extract_domain("not a url")
      {:error, :invalid_url}
  """
  @spec extract_domain(url()) :: {:ok, String.t()} | {:error, :invalid_url}
  def extract_domain(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        {:ok, String.downcase(host)}

      _ ->
        {:error, :invalid_url}
    end
  end

  # Private functions

  defp normalize_scheme(%URI{scheme: scheme} = uri) when is_binary(scheme) do
    %{uri | scheme: String.downcase(scheme)}
  end

  defp normalize_scheme(uri), do: uri

  defp normalize_host(%URI{host: host} = uri) when is_binary(host) do
    %{uri | host: String.downcase(host)}
  end

  defp normalize_host(uri), do: uri

  defp normalize_port(%URI{scheme: "http", port: 80} = uri) do
    %{uri | port: nil}
  end

  defp normalize_port(%URI{scheme: "https", port: 443} = uri) do
    %{uri | port: nil}
  end

  defp normalize_port(uri), do: uri

  defp normalize_path(%URI{path: nil} = uri) do
    %{uri | path: "/"}
  end

  defp normalize_path(%URI{path: ""} = uri) do
    %{uri | path: "/"}
  end

  defp normalize_path(%URI{path: path} = uri) do
    normalized_path =
      path
      |> String.replace(~r/\/+/, "/")
      |> String.trim_trailing("/")

    normalized_path = if normalized_path == "", do: "/", else: normalized_path
    %{uri | path: normalized_path}
  end

  defp normalize_query(%URI{query: nil} = uri), do: uri

  defp normalize_query(%URI{query: query} = uri) do
    sorted_query =
      query
      |> URI.decode_query()
      |> Enum.sort()
      |> URI.encode_query()

    %{uri | query: sorted_query}
  end

  defp remove_fragment(uri) do
    %{uri | fragment: nil}
  end

  defp passes_domain_filter?(_url, []), do: true

  defp passes_domain_filter?(url, allowed_domains) do
    Enum.any?(allowed_domains, &same_domain?(url, &1))
  end

  defp passes_path_filter?(url, allowed_paths, blocked_paths) do
    case URI.parse(url) do
      %URI{path: path} when is_binary(path) ->
        passes_allowed_paths?(path, allowed_paths) &&
          !blocked_by_paths?(path, blocked_paths)

      _ ->
        false
    end
  end

  defp passes_allowed_paths?(_path, []), do: true

  defp passes_allowed_paths?(path, allowed_paths) do
    Enum.any?(allowed_paths, &String.contains?(path, &1))
  end

  defp blocked_by_paths?(path, blocked_paths) do
    Enum.any?(blocked_paths, &String.contains?(path, &1))
  end
end