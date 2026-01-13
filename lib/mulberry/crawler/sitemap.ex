defmodule Mulberry.Crawler.Sitemap do
  @moduledoc """
  Parses and discovers sitemap.xml files for crawling.

  This module provides functionality to:
  - Discover sitemaps from robots.txt or common locations
  - Parse XML sitemaps and sitemap indexes
  - Handle gzipped sitemaps

  ## Usage

      # Discover sitemaps for a domain
      {:ok, sitemap_urls} = Sitemap.discover_sitemaps("example.com")

      # Fetch and parse a sitemap
      {:ok, entries} = Sitemap.fetch_and_parse("https://example.com/sitemap.xml")

  ## Sitemap Formats Supported

  - Standard XML sitemaps (`<urlset>`)
  - Sitemap index files (`<sitemapindex>`)
  - Gzipped sitemaps (.xml.gz)

  ## Entry Structure

  Each sitemap entry contains:
  - `loc` - URL location (required)
  - `lastmod` - Last modification date (optional)
  - `changefreq` - Change frequency hint (optional)
  - `priority` - Priority hint (optional)
  """

  require Logger

  @type sitemap_entry :: %{
          loc: String.t(),
          lastmod: String.t() | nil,
          changefreq: String.t() | nil,
          priority: float() | nil
        }

  @type sitemap_index_entry :: %{
          loc: String.t(),
          lastmod: String.t() | nil
        }

  @common_sitemap_paths [
    "/sitemap.xml",
    "/sitemap_index.xml",
    "/sitemap-index.xml",
    "/sitemaps.xml"
  ]

  @doc """
  Discovers sitemaps for a domain by checking robots.txt and common locations.

  Returns a list of sitemap URLs.

  ## Options
    - `:retriever` - Retriever module to use (default: Mulberry.Retriever.Req)
    - `:check_common` - Whether to check common sitemap paths (default: true)
  """
  @spec discover_sitemaps(String.t(), keyword()) :: {:ok, [String.t()]}
  def discover_sitemaps(domain, opts \\ []) do
    retriever = Keyword.get(opts, :retriever, Mulberry.Retriever.Req)
    check_common = Keyword.get(opts, :check_common, true)

    # Try to get sitemaps from robots.txt
    robots_sitemaps =
      case Mulberry.Crawler.RobotsTxt.get_sitemaps(domain) do
        {:ok, sitemaps} -> sitemaps
        {:error, _} -> []
      end

    # Check common sitemap locations if enabled
    common_sitemaps =
      if check_common && robots_sitemaps == [] do
        discover_common_sitemaps(domain, retriever)
      else
        []
      end

    sitemaps = Enum.uniq(robots_sitemaps ++ common_sitemaps)

    {:ok, sitemaps}
  end

  @doc """
  Fetches and parses a sitemap URL.

  Handles both regular sitemaps and sitemap indexes. For sitemap indexes,
  recursively fetches and parses all referenced sitemaps.

  ## Options
    - `:retriever` - Retriever module to use (default: Mulberry.Retriever.Req)
    - `:max_depth` - Maximum recursion depth for sitemap indexes (default: 2)
    - `:follow_indexes` - Whether to follow sitemap index references (default: true)
  """
  @spec fetch_and_parse(String.t(), keyword()) :: {:ok, [sitemap_entry()]} | {:error, any()}
  def fetch_and_parse(url, opts \\ []) do
    retriever = Keyword.get(opts, :retriever, Mulberry.Retriever.Req)
    max_depth = Keyword.get(opts, :max_depth, 2)
    follow_indexes = Keyword.get(opts, :follow_indexes, true)

    do_fetch_and_parse(url, retriever, max_depth, follow_indexes, 0)
  end

  @doc """
  Parses sitemap XML content.

  Returns a list of sitemap entries or sitemap index entries.
  """
  @spec parse_sitemap_xml(String.t()) ::
          {:ok, :urlset, [sitemap_entry()]}
          | {:ok, :sitemapindex, [sitemap_index_entry()]}
          | {:error, any()}
  def parse_sitemap_xml(xml_content) when is_binary(xml_content) do
    case Floki.parse_document(xml_content) do
      {:ok, doc} ->
        cond do
          sitemap_index?(doc) ->
            entries = parse_sitemap_index(doc)
            {:ok, :sitemapindex, entries}

          urlset?(doc) ->
            entries = parse_urlset(doc)
            {:ok, :urlset, entries}

          true ->
            {:error, :unknown_sitemap_format}
        end

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  def parse_sitemap_xml(_), do: {:error, :invalid_content}

  # Private functions

  defp do_fetch_and_parse(url, retriever, max_depth, follow_indexes, current_depth) do
    if current_depth > max_depth do
      Logger.warning("Max sitemap depth reached for #{url}")
      {:ok, []}
    else
      case fetch_sitemap_content(url, retriever) do
        {:ok, content} ->
          process_sitemap_content(content, retriever, max_depth, follow_indexes, current_depth)

        {:error, reason} ->
          Logger.warning("Failed to fetch sitemap #{url}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp fetch_sitemap_content(url, retriever) do
    case Mulberry.Retriever.get(retriever, url) do
      {:ok, %{status: :ok, content: content}} when is_binary(content) ->
        # Check if content is gzipped
        content = maybe_decompress(content, url)
        {:ok, content}

      {:ok, %{status: :failed}} ->
        {:error, :fetch_failed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_sitemap_content(content, retriever, max_depth, follow_indexes, current_depth) do
    case parse_sitemap_xml(content) do
      {:ok, :urlset, entries} ->
        {:ok, entries}

      {:ok, :sitemapindex, index_entries} when follow_indexes ->
        entries =
          fetch_index_entries(index_entries, retriever, max_depth, follow_indexes, current_depth)

        {:ok, entries}

      {:ok, :sitemapindex, _index_entries} ->
        # Don't follow indexes if disabled
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_index_entries(index_entries, retriever, max_depth, follow_indexes, current_depth) do
    index_entries
    |> Task.async_stream(
      &fetch_sitemap_entry(&1, retriever, max_depth, follow_indexes, current_depth),
      max_concurrency: 3,
      timeout: 30_000
    )
    |> Enum.flat_map(fn
      {:ok, sub_entries} -> sub_entries
      {:exit, _} -> []
    end)
  end

  defp fetch_sitemap_entry(entry, retriever, max_depth, follow_indexes, current_depth) do
    case do_fetch_and_parse(entry.loc, retriever, max_depth, follow_indexes, current_depth + 1) do
      {:ok, sub_entries} -> sub_entries
      {:error, _} -> []
    end
  end

  defp maybe_decompress(content, url) do
    if String.ends_with?(url, ".gz") do
      try do
        :zlib.gunzip(content)
      rescue
        _ ->
          Logger.warning("Failed to decompress gzipped sitemap #{url}")
          content
      end
    else
      content
    end
  end

  defp discover_common_sitemaps(domain, retriever) do
    @common_sitemap_paths
    |> Enum.map(fn path -> "https://#{domain}#{path}" end)
    |> Enum.filter(fn url ->
      case Mulberry.Retriever.get(retriever, url, timeout: 5000) do
        {:ok, %{status: :ok}} -> true
        _ -> false
      end
    end)
  end

  defp sitemap_index?(doc) do
    Floki.find(doc, "sitemapindex") != []
  end

  defp urlset?(doc) do
    Floki.find(doc, "urlset") != []
  end

  defp parse_sitemap_index(doc) do
    doc
    |> Floki.find("sitemapindex sitemap")
    |> Enum.map(fn sitemap ->
      %{
        loc: get_element_text(sitemap, "loc"),
        lastmod: get_element_text(sitemap, "lastmod")
      }
    end)
    |> Enum.reject(fn entry -> is_nil(entry.loc) end)
  end

  defp parse_urlset(doc) do
    doc
    |> Floki.find("urlset url")
    |> Enum.map(fn url_elem ->
      %{
        loc: get_element_text(url_elem, "loc"),
        lastmod: get_element_text(url_elem, "lastmod"),
        changefreq: get_element_text(url_elem, "changefreq"),
        priority: parse_priority(get_element_text(url_elem, "priority"))
      }
    end)
    |> Enum.reject(fn entry -> is_nil(entry.loc) end)
  end

  defp get_element_text(parent, tag) do
    case Floki.find(parent, tag) do
      [] -> nil
      [elem | _] -> elem |> Floki.text() |> String.trim()
    end
  end

  defp parse_priority(nil), do: nil

  defp parse_priority(str) do
    case Float.parse(str) do
      {value, _} -> value
      :error -> nil
    end
  end
end
