defmodule Mulberry.Crawler.StructuredData do
  @moduledoc """
  Extracts structured data from HTML content.

  This module provides functions to extract various types of structured data
  commonly embedded in web pages:

  - **JSON-LD**: Linked data in JSON format, typically used for SEO and search
    engine rich snippets (Schema.org data).
  - **Open Graph**: Meta tags used by social platforms like Facebook for link
    previews.
  - **Twitter Card**: Meta tags used by Twitter for rich card previews.

  ## Usage

      html = "<html>...</html>"

      # Extract all structured data at once
      structured_data = StructuredData.extract_all(html)

      # Or extract specific types
      json_ld = StructuredData.extract_json_ld(html)
      og_data = StructuredData.extract_open_graph(html)
      twitter_data = StructuredData.extract_twitter_card(html)

  ## Examples

      iex> html = \"""
      ...> <html>
      ...> <head>
      ...>   <meta property="og:title" content="My Page">
      ...>   <script type="application/ld+json">{"@type": "Article"}</script>
      ...> </head>
      ...> </html>
      ...> \"""
      iex> StructuredData.extract_all(html)
      %{
        json_ld: [%{"@type" => "Article"}],
        open_graph: %{title: "My Page"},
        twitter_card: nil
      }
  """

  require Logger

  # Allowlist of known Open Graph property keys (atoms are safe since they're defined here)
  @known_og_keys ~w(title description image url type site_name locale updated_time video audio)a

  # Allowlist of known Twitter Card property keys
  @known_twitter_keys ~w(card title description image site creator label1 label2 data1 data2 player player_width player_height)a

  @type json_ld :: [map()]

  @type open_graph :: %{
          optional(:title) => String.t(),
          optional(:description) => String.t(),
          optional(:image) => String.t(),
          optional(:url) => String.t(),
          optional(:type) => String.t(),
          optional(:site_name) => String.t(),
          optional(:locale) => String.t()
        }

  @type twitter_card :: %{
          optional(:card) => String.t(),
          optional(:title) => String.t(),
          optional(:description) => String.t(),
          optional(:image) => String.t(),
          optional(:site) => String.t(),
          optional(:creator) => String.t()
        }

  @type structured_data :: %{
          json_ld: json_ld(),
          open_graph: open_graph() | nil,
          twitter_card: twitter_card() | nil
        }

  @doc """
  Extracts all structured data types from HTML content.

  Returns a map containing:
  - `:json_ld` - List of JSON-LD objects found in the page
  - `:open_graph` - Open Graph meta data or nil if not found
  - `:twitter_card` - Twitter Card meta data or nil if not found
  """
  @spec extract_all(String.t()) :: structured_data()
  def extract_all(html) when is_binary(html) do
    %{
      json_ld: extract_json_ld(html),
      open_graph: extract_open_graph(html),
      twitter_card: extract_twitter_card(html)
    }
  end

  def extract_all(_), do: %{json_ld: [], open_graph: nil, twitter_card: nil}

  @doc """
  Extracts JSON-LD structured data from HTML content.

  JSON-LD (JavaScript Object Notation for Linked Data) is commonly used for
  embedding Schema.org data in web pages for SEO purposes.

  Returns a list of parsed JSON objects. Invalid JSON is logged and skipped.

  ## Examples

      iex> html = \"""
      ...> <script type="application/ld+json">
      ...> {"@context": "https://schema.org", "@type": "Article", "name": "Test"}
      ...> </script>
      ...> \"""
      iex> StructuredData.extract_json_ld(html)
      [%{"@context" => "https://schema.org", "@type" => "Article", "name" => "Test"}]
  """
  @spec extract_json_ld(String.t()) :: json_ld()
  def extract_json_ld(html) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, html_tree} ->
        html_tree
        |> Floki.find("script[type='application/ld+json']")
        |> Enum.map(&extract_script_content/1)
        |> Enum.map(&parse_json/1)
        |> Enum.reject(&is_nil/1)
        |> List.flatten()

      {:error, _} ->
        []
    end
  end

  def extract_json_ld(_), do: []

  @doc """
  Extracts Open Graph meta tags from HTML content.

  Open Graph protocol is used by Facebook and other platforms to generate
  rich link previews.

  Returns a map with Open Graph properties or nil if no OG tags are found.

  ## Examples

      iex> html = \"""
      ...> <meta property="og:title" content="My Article">
      ...> <meta property="og:description" content="A great article">
      ...> <meta property="og:image" content="https://example.com/image.jpg">
      ...> \"""
      iex> StructuredData.extract_open_graph(html)
      %{title: "My Article", description: "A great article", image: "https://example.com/image.jpg"}
  """
  @spec extract_open_graph(String.t()) :: open_graph() | nil
  def extract_open_graph(html) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, html_tree} ->
        og_data =
          html_tree
          |> Floki.find("meta[property^='og:']")
          |> Enum.reduce(%{}, &extract_og_meta/2)

        if map_size(og_data) > 0, do: og_data, else: nil

      {:error, _} ->
        nil
    end
  end

  def extract_open_graph(_), do: nil

  @doc """
  Extracts Twitter Card meta tags from HTML content.

  Twitter Cards allow rich media experiences when links are shared on Twitter.

  Returns a map with Twitter Card properties or nil if no Twitter tags are found.

  ## Examples

      iex> html = \"""
      ...> <meta name="twitter:card" content="summary_large_image">
      ...> <meta name="twitter:title" content="My Tweet">
      ...> <meta name="twitter:site" content="@mysite">
      ...> \"""
      iex> StructuredData.extract_twitter_card(html)
      %{card: "summary_large_image", title: "My Tweet", site: "@mysite"}
  """
  @spec extract_twitter_card(String.t()) :: twitter_card() | nil
  def extract_twitter_card(html) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, html_tree} ->
        # Twitter uses both name="twitter:*" and property="twitter:*"
        twitter_data =
          html_tree
          |> find_twitter_meta_tags()
          |> Enum.reduce(%{}, &reduce_twitter_meta/2)

        if map_size(twitter_data) > 0, do: twitter_data, else: nil

      {:error, _} ->
        nil
    end
  end

  def extract_twitter_card(_), do: nil

  # Private functions

  # Extract text content from a script tag node
  # Script tags have structure: {"script", attrs, [content]}
  defp extract_script_content({_tag, _attrs, children}) do
    children
    |> Enum.filter(&is_binary/1)
    |> Enum.join("")
  end

  defp extract_script_content(_), do: ""

  defp parse_json(json_string) when is_binary(json_string) do
    trimmed = String.trim(json_string)

    if trimmed == "" do
      nil
    else
      case Jason.decode(trimmed) do
        {:ok, data} when is_list(data) ->
          # Handle arrays of JSON-LD objects
          data

        {:ok, data} when is_map(data) ->
          [data]

        {:error, error} ->
          Logger.debug("Failed to parse JSON-LD: #{inspect(error)}")
          nil
      end
    end
  end

  defp parse_json(_), do: nil

  defp find_twitter_meta_tags(html_tree) do
    # Find both name="twitter:*" and property="twitter:*" patterns
    by_name = Floki.find(html_tree, "meta[name^='twitter:']")
    by_property = Floki.find(html_tree, "meta[property^='twitter:']")
    by_name ++ by_property
  end

  defp extract_twitter_meta(meta) do
    name = meta |> Floki.attribute("name") |> List.first()
    property = meta |> Floki.attribute("property") |> List.first()
    content = meta |> Floki.attribute("content") |> List.first()

    twitter_key = name || property

    if twitter_key && content do
      key =
        twitter_key
        |> String.replace_prefix("twitter:", "")
        |> to_atom_key(@known_twitter_keys)

      {key, content}
    else
      {nil, nil}
    end
  end

  # Safely convert a string to an atom key, using an allowlist to prevent atom table exhaustion.
  # Unknown keys are kept as strings to maintain flexibility without security risk.
  @spec to_atom_key(String.t(), [atom()]) :: atom() | String.t()
  defp to_atom_key(string, known_keys) when is_binary(string) and is_list(known_keys) do
    normalized =
      string
      |> String.downcase()
      |> String.replace("-", "_")

    # Try to convert to existing atom and check if it's in our allowlist
    try do
      atom_key = String.to_existing_atom(normalized)

      if atom_key in known_keys do
        atom_key
      else
        # Known atom but not in allowlist - keep as string for safety
        normalized
      end
    rescue
      ArgumentError ->
        # Atom doesn't exist - keep as string (safe)
        normalized
    end
  end

  defp extract_og_meta(meta, acc) do
    property = meta |> Floki.attribute("property") |> List.first()
    content = meta |> Floki.attribute("content") |> List.first()

    if property && content do
      key =
        property
        |> String.replace_prefix("og:", "")
        |> to_atom_key(@known_og_keys)

      Map.put(acc, key, content)
    else
      acc
    end
  end

  defp reduce_twitter_meta(meta, acc) do
    {key, content} = extract_twitter_meta(meta)

    if key && content do
      Map.put(acc, key, content)
    else
      acc
    end
  end
end
