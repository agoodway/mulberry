defmodule DataForSEO.Schemas.GoogleAnswer do
  @moduledoc """
  Schema representing a Google My Business answer element.

  Answers are responses to questions on a Google Business Profile, provided by
  either the business owner or other users.
  """

  @derive Jason.Encoder

  @type t :: %__MODULE__{
          type: String.t() | nil,
          answer_id: String.t() | nil,
          profile_image_url: String.t() | nil,
          profile_url: String.t() | nil,
          profile_name: String.t() | nil,
          answer_text: String.t() | nil,
          original_answer_text: String.t() | nil,
          time_ago: String.t() | nil,
          timestamp: String.t() | nil
        }

  defstruct [
    :type,
    :answer_id,
    :profile_image_url,
    :profile_url,
    :profile_name,
    :answer_text,
    :original_answer_text,
    :time_ago,
    :timestamp
  ]

  @doc """
  Creates a new GoogleAnswer struct from API response attributes.

  ## Parameters

  - `attrs` - Map containing answer data from the API response

  ## Returns

  A `GoogleAnswer` struct with all fields populated from the attributes map.

  ## Examples

      iex> attrs = %{
      ...>   "type" => "google_business_answer_element",
      ...>   "answer_id" => "123",
      ...>   "answer_text" => "Yes, we are open on weekends"
      ...> }
      iex> answer = DataForSEO.Schemas.GoogleAnswer.new(attrs)
      iex> answer.answer_text
      "Yes, we are open on weekends"

  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      type: attrs["type"],
      answer_id: attrs["answer_id"],
      profile_image_url: attrs["profile_image_url"],
      profile_url: attrs["profile_url"],
      profile_name: attrs["profile_name"],
      answer_text: attrs["answer_text"],
      original_answer_text: attrs["original_answer_text"],
      time_ago: attrs["time_ago"],
      timestamp: attrs["timestamp"]
    }
  end
end
