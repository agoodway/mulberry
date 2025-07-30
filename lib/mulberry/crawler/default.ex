defmodule Mulberry.Crawler.Default do
  @moduledoc """
  Default implementation of the Mulberry.Crawler.Behaviour.

  This implementation provides sensible defaults for crawling websites:
  - Crawls URLs from the same domain
  - Extracts all links from HTML pages
  - Extracts basic page metadata (title, description, content)
  - Respects common crawling conventions
  """

  @behaviour Mulberry.Crawler.Behaviour

  require Logger
  alias Mulberry.Crawler.URLManager
  alias Mulberry.Document.WebPage

  @impl true
  def should_crawl?(url, context) do
    cond do
      # Don't crawl if we've exceeded max depth
      context.current_depth > context.max_depth ->
        false

      # For website mode, only crawl same domain
      context.mode == :website && context.start_url != "" ->
        case URLManager.extract_domain(context.start_url) do
          {:ok, start_domain} ->
            URLManager.same_domain?(url, start_domain) && 
              !should_skip_url?(url)
          _ ->
            false
        end

      # For URL list mode, crawl any valid URL
      context.mode == :url_list ->
        !should_skip_url?(url)

      true ->
        false
    end
  end

  @impl true
  def extract_data(%WebPage{} = document, url) do
    data = %{
      url: url,
      title: extract_title(document),
      description: extract_description(document),
      content: get_content(document),
      meta: extract_meta_tags(document),
      crawled_at: DateTime.utc_now()
    }

    {:ok, data}
  rescue
    error ->
      Logger.error("Failed to extract data from #{url}: #{inspect(error)}")
      {:error, {:extraction_failed, error}}
  end

  @impl true
  def extract_urls(%WebPage{content: content}, base_url) when is_binary(content) do
    try do
      # Parse HTML content
      html_tree = Floki.parse_document!(content)
      
      # Extract all links
      links = 
        html_tree
        |> Floki.find("a[href]")
        |> Floki.attribute("href")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == "" || String.starts_with?(&1, "#")))
        |> Enum.uniq()
      
      # Resolve relative URLs
      absolute_urls = 
        links
        |> Enum.map(fn link ->
          case URLManager.resolve_url(link, base_url) do
            {:ok, url} -> url
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.filter(&valid_url_scheme?/1)
      
      {:ok, absolute_urls}
    rescue
      error ->
        Logger.error("Failed to extract URLs from #{base_url}: #{inspect(error)}")
        {:ok, []}
    end
  end

  def extract_urls(_document, _base_url) do
    {:ok, []}
  end

  @impl true
  def on_url_success(url, result, _context) do
    Logger.debug("Successfully crawled #{url} - extracted #{map_size(result.data)} data fields and #{length(result.urls)} URLs")
    :ok
  end

  @impl true
  def on_url_failure(url, reason, _context) do
    Logger.warning("Failed to crawl #{url}: #{inspect(reason)}")
    :ok
  end

  @impl true
  def on_complete(results) do
    Logger.info("Crawl completed with #{length(results)} pages")
    :ok
  end

  # Private helper functions

  defp get_content(%WebPage{markdown: markdown, content: content}) do
    cond do
      # Prefer markdown if available and non-empty
      is_binary(markdown) and String.trim(markdown) != "" -> 
        markdown
      
      # Fallback to extracting readable text from HTML
      is_binary(content) and content != "" -> 
        case Floki.parse_document(content) do
          {:ok, html_tree} ->
            Mulberry.HTML.to_readable_text(html_tree)
          _ ->
            # If parsing fails, return the raw HTML as last resort
            content
        end
      
      true -> 
        nil
    end
  end

  defp should_skip_url?(url) do
    # Skip common non-content URLs
    skip_patterns = [
      ~r/\.(jpg|jpeg|png|gif|pdf|zip|exe|dmg|mp3|mp4|avi|mov)$/i,
      ~r/^mailto:/,
      ~r/^tel:/,
      ~r/^javascript:/,
      ~r/^ftp:/,
      ~r/\#$/
    ]
    
    Enum.any?(skip_patterns, &Regex.match?(&1, url))
  end

  defp valid_url_scheme?(url) do
    String.starts_with?(url, "http://") || String.starts_with?(url, "https://")
  end

  defp extract_title(%WebPage{title: title}) when is_binary(title) and title != "" do
    title
  end

  defp extract_title(%WebPage{content: content}) when is_binary(content) do
    try do
      html_tree = Floki.parse_document!(content)
      
      html_tree
      |> Floki.find("title")
      |> Floki.text()
      |> String.trim()
      |> case do
        "" -> nil
        title -> title
      end
    rescue
      _ -> nil
    end
  end

  defp extract_title(_), do: nil

  defp extract_description(%WebPage{description: desc}) when is_binary(desc) and desc != "" do
    desc
  end

  defp extract_description(%WebPage{content: content}) when is_binary(content) do
    try do
      html_tree = Floki.parse_document!(content)
      
      # Try meta description first
      meta_description = 
        html_tree
        |> Floki.find("meta[name='description']")
        |> Floki.attribute("content")
        |> List.first()
      
      # Try og:description if no meta description
      og_description = 
        if is_nil(meta_description) do
          html_tree
          |> Floki.find("meta[property='og:description']")
          |> Floki.attribute("content")
          |> List.first()
        else
          meta_description
        end
      
      case og_description do
        nil -> nil
        desc -> String.trim(desc)
      end
    rescue
      _ -> nil
    end
  end

  defp extract_description(_), do: nil

  defp extract_meta_tags(%WebPage{meta: meta}) when is_list(meta) and length(meta) > 0 do
    meta
  end

  defp extract_meta_tags(%WebPage{content: content}) when is_binary(content) do
    try do
      html_tree = Floki.parse_document!(content)
      
      # Extract various meta tags
      meta_tags = 
        html_tree
        |> Floki.find("meta")
        |> Enum.map(fn meta ->
          name = Floki.attribute(meta, "name") |> List.first()
          property = Floki.attribute(meta, "property") |> List.first()
          content = Floki.attribute(meta, "content") |> List.first()
          
          key = name || property
          
          if key && content do
            {key, content}
          else
            nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.into(%{})
      
      meta_tags
    rescue
      _ -> %{}
    end
  end

  defp extract_meta_tags(_), do: %{}
end