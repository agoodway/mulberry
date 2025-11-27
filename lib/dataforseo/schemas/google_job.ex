defmodule DataForSEO.Schemas.GoogleJob do
  @moduledoc """
  Schema for a single Google job listing from DataForSEO Jobs API.

  Represents a job posting from Google Jobs search results with details including
  job title, employer information, location, contract type, salary, and source.

  ## Fields

  - `:job_id` - Unique identifier for the job posting
  - `:title` - Job title/position name
  - `:employer_name` - Name of the hiring company
  - `:employer_url` - Link to employer's website or job page
  - `:employer_image_url` - Employer's logo URL
  - `:location` - Job location (city, state, country)
  - `:contract_type` - Employment type (e.g., "Full-time", "Part-time", "Contract")
  - `:salary` - Salary information (e.g., "$80,000 - $100,000 a year")
  - `:source_name` - Job board or platform name (e.g., "LinkedIn", "Indeed")
  - `:source_url` - Direct link to the job posting on the source platform
  - `:timestamp` - Publication date/time in UTC
  - `:time_ago` - Relative time format (e.g., "2 days ago")
  - `:rank_group` - Ranking group number
  - `:rank_absolute` - Absolute position across all SERP elements
  - `:position` - Position within results
  - `:xpath` - DOM location xpath
  - `:type` - Item type (always "google_jobs_item")
  """

  @type t :: %__MODULE__{
          job_id: String.t() | nil,
          title: String.t() | nil,
          employer_name: String.t() | nil,
          employer_url: String.t() | nil,
          employer_image_url: String.t() | nil,
          location: String.t() | nil,
          contract_type: String.t() | nil,
          salary: String.t() | nil,
          source_name: String.t() | nil,
          source_url: String.t() | nil,
          timestamp: String.t() | nil,
          time_ago: String.t() | nil,
          rank_group: integer() | nil,
          rank_absolute: integer() | nil,
          position: integer() | nil,
          xpath: String.t() | nil,
          type: String.t() | nil
        }

  defstruct [
    :job_id,
    :title,
    :employer_name,
    :employer_url,
    :employer_image_url,
    :location,
    :contract_type,
    :salary,
    :source_name,
    :source_url,
    :timestamp,
    :time_ago,
    :rank_group,
    :rank_absolute,
    :position,
    :xpath,
    :type
  ]

  @doc """
  Creates a GoogleJob struct from a map of attributes.

  ## Parameters

  - `attrs` - Map of job attributes from the API response

  ## Returns

  A `GoogleJob` struct with all fields populated from the attributes map.

  ## Examples

      iex> DataForSEO.Schemas.GoogleJob.new(%{
      ...>   "job_id" => "abc123",
      ...>   "title" => "Senior Elixir Developer",
      ...>   "employer_name" => "Tech Corp",
      ...>   "contract_type" => "Full-time",
      ...>   "location" => "San Francisco, CA"
      ...> })
      %DataForSEO.Schemas.GoogleJob{
        job_id: "abc123",
        title: "Senior Elixir Developer",
        employer_name: "Tech Corp",
        contract_type: "Full-time",
        location: "San Francisco, CA"
      }

  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      job_id: attrs["job_id"],
      title: attrs["title"],
      employer_name: attrs["employer_name"],
      employer_url: attrs["employer_url"],
      employer_image_url: attrs["employer_image_url"],
      location: attrs["location"],
      contract_type: attrs["contract_type"],
      salary: attrs["salary"],
      source_name: attrs["source_name"],
      source_url: attrs["source_url"],
      timestamp: attrs["timestamp"],
      time_ago: attrs["time_ago"],
      rank_group: attrs["rank_group"],
      rank_absolute: attrs["rank_absolute"],
      position: attrs["position"],
      xpath: attrs["xpath"],
      type: attrs["type"]
    }
  end
end
