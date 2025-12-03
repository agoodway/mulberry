defmodule DataForSEO.Schemas.GoogleOrganicResult do
  @moduledoc """
  Schema for Google Organic SERP results from DataForSEO Organic API.

  Contains a collection of organic search results and People Also Ask questions
  along with metadata about the search query and parameters used.

  ## Fields

  - `:keyword` - Search keyword/query
  - `:location_code` - Location code used for search
  - `:language_code` - Language code used for search
  - `:se_domain` - Google domain used (e.g., "google.com")
  - `:check_url` - Direct link to Google SERP page
  - `:datetime` - Retrieval timestamp
  - `:se_results_count` - Total results in SERP
  - `:items_count` - Number of items in this result
  - `:organic_items` - List of `DataForSEO.Schemas.GoogleOrganicItem` structs
  - `:people_also_ask` - List of People Also Ask question structs
  - `:type` - Result type (always "organic")

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleOrganicResult{
      ...>   keyword: "elixir programming",
      ...>   items_count: 50,
      ...>   organic_items: [%DataForSEO.Schemas.GoogleOrganicItem{title: "Elixir Lang"}],
      ...>   people_also_ask: [%{question: "What is Elixir?"}]
      ...> }
      %DataForSEO.Schemas.GoogleOrganicResult{keyword: "elixir programming", items_count: 50, ...}

  """

  alias DataForSEO.Schemas.GoogleOrganicItem

  @type people_also_ask_item :: %{
          question: String.t() | nil,
          answer: String.t() | nil,
          url: String.t() | nil,
          domain: String.t() | nil,
          title: String.t() | nil,
          xpath: String.t() | nil
        }

  @type t :: %__MODULE__{
          keyword: String.t() | nil,
          location_code: integer() | nil,
          language_code: String.t() | nil,
          se_domain: String.t() | nil,
          check_url: String.t() | nil,
          datetime: String.t() | nil,
          se_results_count: integer() | nil,
          items_count: integer() | nil,
          type: String.t() | nil,
          organic_items: [GoogleOrganicItem.t()],
          people_also_ask: [people_also_ask_item()]
        }

  defstruct [
    :keyword,
    :location_code,
    :language_code,
    :se_domain,
    :check_url,
    :datetime,
    :se_results_count,
    :items_count,
    :type,
    organic_items: [],
    people_also_ask: []
  ]

  @doc """
  Creates a GoogleOrganicResult struct from a map of attributes.

  Parses the result data from the DataForSEO API response and separates
  organic results from People Also Ask questions based on item type.

  ## Parameters

  - `attrs` - Map containing the result data from the API response

  ## Returns

  A `GoogleOrganicResult` struct with parsed organic items and PAA questions.

  ## Examples

      iex> DataForSEO.Schemas.GoogleOrganicResult.new(%{
      ...>   "keyword" => "elixir programming",
      ...>   "items_count" => 50,
      ...>   "items" => [
      ...>     %{"type" => "organic", "title" => "Elixir Official"},
      ...>     %{"type" => "people_also_ask", "question" => "What is Elixir?"}
      ...>   ]
      ...> })
      %DataForSEO.Schemas.GoogleOrganicResult{
        keyword: "elixir programming",
        organic_items: [%DataForSEO.Schemas.GoogleOrganicItem{...}],
        people_also_ask: [%{question: "What is Elixir?", ...}]
      }

  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    items = Map.get(attrs, "items", [])

    organic_items =
      items
      |> Enum.filter(fn item -> item["type"] == "organic" end)
      |> Enum.map(&GoogleOrganicItem.new/1)

    people_also_ask =
      items
      |> Enum.filter(fn item -> item["type"] == "people_also_ask" end)
      |> Enum.flat_map(fn paa_container ->
        # PAA items have nested "items" array with the actual questions
        case paa_container["items"] do
          items when is_list(items) -> Enum.map(items, &parse_people_also_ask/1)
          _ -> []
        end
      end)

    %__MODULE__{
      keyword: attrs["keyword"],
      location_code: attrs["location_code"],
      language_code: attrs["language_code"],
      se_domain: attrs["se_domain"],
      check_url: attrs["check_url"],
      datetime: attrs["datetime"],
      se_results_count: attrs["se_results_count"],
      items_count: attrs["items_count"],
      type: attrs["type"],
      organic_items: organic_items,
      people_also_ask: people_also_ask
    }
  end

  @doc """
  Returns the number of organic search results.

  ## Parameters

  - `result` - A `GoogleOrganicResult` struct

  ## Returns

  The count of organic results in the result set.

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleOrganicResult{organic_items: [%{}, %{}, %{}]}
      iex> DataForSEO.Schemas.GoogleOrganicResult.organic_result_count(result)
      3

  """
  @spec organic_result_count(t()) :: non_neg_integer()
  def organic_result_count(%__MODULE__{organic_items: items}), do: length(items)

  @doc """
  Returns the number of People Also Ask questions.

  ## Parameters

  - `result` - A `GoogleOrganicResult` struct

  ## Returns

  The count of People Also Ask questions in the result set.

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleOrganicResult{people_also_ask: [%{}, %{}]}
      iex> DataForSEO.Schemas.GoogleOrganicResult.people_also_ask_count(result)
      2

  """
  @spec people_also_ask_count(t()) :: non_neg_integer()
  def people_also_ask_count(%__MODULE__{people_also_ask: questions}), do: length(questions)

  @doc """
  Extracts all People Also Ask questions and answers.

  Returns a list of maps containing question, answer, and source information
  for all People Also Ask items in the result.

  ## Parameters

  - `result` - A `GoogleOrganicResult` struct

  ## Returns

  A list of maps with question, answer, url, domain, and title information.

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleOrganicResult{
      ...>   people_also_ask: [
      ...>     %{question: "What is Elixir?", answer: "A functional language..."},
      ...>     %{question: "Is Elixir fast?", answer: "Yes, very fast..."}
      ...>   ]
      ...> }
      iex> DataForSEO.Schemas.GoogleOrganicResult.extract_people_also_ask_questions(result)
      [
        %{question: "What is Elixir?", answer: "A functional language...", ...},
        %{question: "Is Elixir fast?", answer: "Yes, very fast...", ...}
      ]

  """
  @spec extract_people_also_ask_questions(t()) :: [people_also_ask_item()]
  def extract_people_also_ask_questions(%__MODULE__{people_also_ask: questions}) do
    questions
  end

  @doc """
  Filters organic results by domain.

  ## Parameters

  - `result` - A `GoogleOrganicResult` struct
  - `domain` - The domain to filter by (e.g., "example.com")

  ## Returns

  A list of `GoogleOrganicItem` structs matching the domain.

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleOrganicResult{
      ...>   organic_items: [
      ...>     %DataForSEO.Schemas.GoogleOrganicItem{domain: "example.com"},
      ...>     %DataForSEO.Schemas.GoogleOrganicItem{domain: "other.com"}
      ...>   ]
      ...> }
      iex> DataForSEO.Schemas.GoogleOrganicResult.filter_by_domain(result, "example.com")
      [%DataForSEO.Schemas.GoogleOrganicItem{domain: "example.com"}]

  """
  @spec filter_by_domain(t(), String.t()) :: [GoogleOrganicItem.t()]
  def filter_by_domain(%__MODULE__{organic_items: items}, domain) do
    Enum.filter(items, fn item -> item.domain == domain end)
  end

  @doc """
  Filters organic results that have ratings.

  ## Parameters

  - `result` - A `GoogleOrganicResult` struct

  ## Returns

  A list of `GoogleOrganicItem` structs that have rating information.

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleOrganicResult{
      ...>   organic_items: [
      ...>     %DataForSEO.Schemas.GoogleOrganicItem{rating: %{value: 4.5}},
      ...>     %DataForSEO.Schemas.GoogleOrganicItem{rating: nil}
      ...>   ]
      ...> }
      iex> rated = DataForSEO.Schemas.GoogleOrganicResult.filter_with_ratings(result)
      iex> length(rated)
      1

  """
  @spec filter_with_ratings(t()) :: [GoogleOrganicItem.t()]
  def filter_with_ratings(%__MODULE__{organic_items: items}) do
    Enum.filter(items, &GoogleOrganicItem.has_rating?/1)
  end

  @doc """
  Filters organic results that have sitelinks.

  ## Parameters

  - `result` - A `GoogleOrganicResult` struct

  ## Returns

  A list of `GoogleOrganicItem` structs that have sitelinks.

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleOrganicResult{
      ...>   organic_items: [
      ...>     %DataForSEO.Schemas.GoogleOrganicItem{sitelinks: [%{title: "About"}]},
      ...>     %DataForSEO.Schemas.GoogleOrganicItem{sitelinks: []}
      ...>   ]
      ...> }
      iex> with_sitelinks = DataForSEO.Schemas.GoogleOrganicResult.filter_with_sitelinks(result)
      iex> length(with_sitelinks)
      1

  """
  @spec filter_with_sitelinks(t()) :: [GoogleOrganicItem.t()]
  def filter_with_sitelinks(%__MODULE__{organic_items: items}) do
    Enum.filter(items, &GoogleOrganicItem.has_sitelinks?/1)
  end

  @doc """
  Returns the top domains by result count.

  ## Parameters

  - `result` - A `GoogleOrganicResult` struct
  - `limit` - Maximum number of domains to return (default: 5)

  ## Returns

  A list of tuples {domain, count} sorted by count descending.

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleOrganicResult{
      ...>   organic_items: [
      ...>     %DataForSEO.Schemas.GoogleOrganicItem{domain: "example.com"},
      ...>     %DataForSEO.Schemas.GoogleOrganicItem{domain: "example.com"},
      ...>     %DataForSEO.Schemas.GoogleOrganicItem{domain: "other.com"}
      ...>   ]
      ...> }
      iex> DataForSEO.Schemas.GoogleOrganicResult.top_domains(result, 2)
      [{"example.com", 2}, {"other.com", 1}]

  """
  @spec top_domains(t(), non_neg_integer()) :: [{String.t(), non_neg_integer()}]
  def top_domains(%__MODULE__{organic_items: items}, limit \\ 5) do
    items
    |> Enum.map(& &1.domain)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_domain, count} -> -count end)
    |> Enum.take(limit)
  end

  @doc """
  Groups organic results by domain.

  ## Parameters

  - `result` - A `GoogleOrganicResult` struct

  ## Returns

  A map where keys are domain names and values are lists of organic items from that domain.

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleOrganicResult{
      ...>   organic_items: [
      ...>     %DataForSEO.Schemas.GoogleOrganicItem{domain: "example.com", title: "Page 1"},
      ...>     %DataForSEO.Schemas.GoogleOrganicItem{domain: "example.com", title: "Page 2"}
      ...>   ]
      ...> }
      iex> grouped = DataForSEO.Schemas.GoogleOrganicResult.group_by_domain(result)
      iex> map_size(grouped)
      1

  """
  @spec group_by_domain(t()) :: %{String.t() => [GoogleOrganicItem.t()]}
  def group_by_domain(%__MODULE__{organic_items: items}) do
    Enum.group_by(items, fn item -> item.domain end)
  end

  # Private helpers

  defp parse_people_also_ask(item) when is_map(item) do
    %{
      question: item["title"] || item["question"],
      answer: parse_answer(item),
      url: item["url"],
      domain: item["domain"],
      title: item["description"] || item["snippet"],
      xpath: item["xpath"]
    }
  end

  defp parse_answer(item) do
    cond do
      item["answer"] -> item["answer"]
      item["expanded_element"] -> extract_expanded_text(item["expanded_element"])
      item["description"] -> item["description"]
      true -> nil
    end
  end

  defp extract_expanded_text(nil), do: nil

  defp extract_expanded_text(expanded) when is_list(expanded) do
    expanded
    |> Enum.map(fn elem -> elem["description"] || elem["text"] end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp extract_expanded_text(expanded) when is_map(expanded) do
    expanded["description"] || expanded["text"]
  end
end
