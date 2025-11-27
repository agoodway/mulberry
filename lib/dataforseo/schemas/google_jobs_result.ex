defmodule DataForSEO.Schemas.GoogleJobsResult do
  @moduledoc """
  Schema for Google jobs search results from DataForSEO Jobs API.

  Contains a collection of job listings along with metadata about the search
  query and parameters used.

  ## Fields

  - `:keyword` - Job search keyword/title
  - `:location_code` - Location code used for search
  - `:language_code` - Language code used for search
  - `:se_domain` - Google domain used (e.g., "google.com")
  - `:check_url` - Direct link to Google Jobs search page
  - `:datetime` - Retrieval timestamp
  - `:items_count` - Number of jobs in this result
  - `:jobs` - List of `DataForSEO.Schemas.GoogleJob` structs
  - `:type` - Result type (always "jobs")

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleJobsResult{
      ...>   keyword: "elixir developer",
      ...>   items_count: 50,
      ...>   jobs: [%DataForSEO.Schemas.GoogleJob{title: "Senior Elixir Engineer"}]
      ...> }
      %DataForSEO.Schemas.GoogleJobsResult{keyword: "elixir developer", items_count: 50, ...}

  """

  alias DataForSEO.Schemas.GoogleJob

  @type t :: %__MODULE__{
          keyword: String.t() | nil,
          location_code: integer() | nil,
          language_code: String.t() | nil,
          se_domain: String.t() | nil,
          check_url: String.t() | nil,
          datetime: String.t() | nil,
          items_count: integer() | nil,
          jobs: [GoogleJob.t()],
          type: String.t() | nil
        }

  defstruct [
    :keyword,
    :location_code,
    :language_code,
    :se_domain,
    :check_url,
    :datetime,
    :items_count,
    :type,
    jobs: []
  ]

  @doc """
  Creates a GoogleJobsResult struct from a map of attributes.

  Parses the result data from the DataForSEO API response and converts
  each job item into a `GoogleJob` struct.

  ## Parameters

  - `attrs` - Map containing the result data from the API response

  ## Returns

  A `GoogleJobsResult` struct with parsed job listings.

  ## Examples

      iex> DataForSEO.Schemas.GoogleJobsResult.new(%{
      ...>   "keyword" => "elixir developer",
      ...>   "items_count" => 50,
      ...>   "items" => [
      ...>     %{"title" => "Senior Elixir Engineer", "employer_name" => "Tech Corp"}
      ...>   ]
      ...> })
      %DataForSEO.Schemas.GoogleJobsResult{
        keyword: "elixir developer",
        items_count: 50,
        jobs: [%DataForSEO.Schemas.GoogleJob{title: "Senior Elixir Engineer", ...}]
      }

  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    jobs =
      attrs
      |> Map.get("items", [])
      |> Enum.map(&GoogleJob.new/1)

    %__MODULE__{
      keyword: attrs["keyword"],
      location_code: attrs["location_code"],
      language_code: attrs["language_code"],
      se_domain: attrs["se_domain"],
      check_url: attrs["check_url"],
      datetime: attrs["datetime"],
      items_count: attrs["items_count"],
      type: attrs["type"],
      jobs: jobs
    }
  end

  @doc """
  Returns the number of jobs in the result.

  ## Parameters

  - `result` - A `GoogleJobsResult` struct

  ## Returns

  The count of job listings in the result.

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleJobsResult{jobs: [%{}, %{}, %{}]}
      iex> DataForSEO.Schemas.GoogleJobsResult.job_count(result)
      3

  """
  @spec job_count(t()) :: non_neg_integer()
  def job_count(%__MODULE__{jobs: jobs}), do: length(jobs)

  @doc """
  Filters jobs by contract type.

  ## Parameters

  - `result` - A `GoogleJobsResult` struct
  - `contract_type` - The contract type to filter by (e.g., "Full-time", "Part-time")

  ## Returns

  A list of `GoogleJob` structs matching the contract type.

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleJobsResult{
      ...>   jobs: [
      ...>     %DataForSEO.Schemas.GoogleJob{contract_type: "Full-time"},
      ...>     %DataForSEO.Schemas.GoogleJob{contract_type: "Part-time"}
      ...>   ]
      ...> }
      iex> DataForSEO.Schemas.GoogleJobsResult.filter_by_contract_type(result, "Full-time")
      [%DataForSEO.Schemas.GoogleJob{contract_type: "Full-time"}]

  """
  @spec filter_by_contract_type(t(), String.t()) :: [GoogleJob.t()]
  def filter_by_contract_type(%__MODULE__{jobs: jobs}, contract_type) do
    Enum.filter(jobs, fn job ->
      job.contract_type == contract_type
    end)
  end

  @doc """
  Groups jobs by employer name.

  ## Parameters

  - `result` - A `GoogleJobsResult` struct

  ## Returns

  A map where keys are employer names and values are lists of jobs from that employer.

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleJobsResult{
      ...>   jobs: [
      ...>     %DataForSEO.Schemas.GoogleJob{employer_name: "TechCorp"},
      ...>     %DataForSEO.Schemas.GoogleJob{employer_name: "TechCorp"}
      ...>   ]
      ...> }
      iex> DataForSEO.Schemas.GoogleJobsResult.group_by_employer(result)
      %{"TechCorp" => [%DataForSEO.Schemas.GoogleJob{...}, %DataForSEO.Schemas.GoogleJob{...}]}

  """
  @spec group_by_employer(t()) :: %{String.t() => [GoogleJob.t()]}
  def group_by_employer(%__MODULE__{jobs: jobs}) do
    Enum.group_by(jobs, fn job -> job.employer_name end)
  end
end
