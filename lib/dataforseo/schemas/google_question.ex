defmodule DataForSEO.Schemas.GoogleQuestion do
  @moduledoc """
  Schema representing a Google My Business question item.

  Questions are user-submitted inquiries on a Google Business Profile. Each question
  can have up to 5 answers from the business owner or other users.
  """

  @derive Jason.Encoder

  alias DataForSEO.Schemas.GoogleAnswer

  @type t :: %__MODULE__{
          type: String.t() | nil,
          rank_group: integer() | nil,
          rank_absolute: integer() | nil,
          question_id: String.t() | nil,
          url: String.t() | nil,
          profile_image_url: String.t() | nil,
          profile_url: String.t() | nil,
          profile_name: String.t() | nil,
          question_text: String.t() | nil,
          original_question_text: String.t() | nil,
          time_ago: String.t() | nil,
          timestamp: String.t() | nil,
          answers: [GoogleAnswer.t()]
        }

  defstruct [
    :type,
    :rank_group,
    :rank_absolute,
    :question_id,
    :url,
    :profile_image_url,
    :profile_url,
    :profile_name,
    :question_text,
    :original_question_text,
    :time_ago,
    :timestamp,
    answers: []
  ]

  @doc """
  Creates a new GoogleQuestion struct from API response attributes.

  ## Parameters

  - `attrs` - Map containing question data from the API response

  ## Returns

  A `GoogleQuestion` struct with all fields populated from the attributes map,
  including nested answer elements.

  ## Examples

      iex> attrs = %{
      ...>   "question_id" => "123",
      ...>   "question_text" => "Are you open on weekends?",
      ...>   "items" => [
      ...>     %{"answer_id" => "456", "answer_text" => "Yes"}
      ...>   ]
      ...> }
      iex> question = DataForSEO.Schemas.GoogleQuestion.new(attrs)
      iex> question.question_text
      "Are you open on weekends?"
      iex> length(question.answers)
      1

  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    answers =
      (attrs["items"] || [])
      |> Enum.map(&GoogleAnswer.new/1)

    %__MODULE__{
      type: attrs["type"],
      rank_group: attrs["rank_group"],
      rank_absolute: attrs["rank_absolute"],
      question_id: attrs["question_id"],
      url: attrs["url"],
      profile_image_url: attrs["profile_image_url"],
      profile_url: attrs["profile_url"],
      profile_name: attrs["profile_name"],
      question_text: attrs["question_text"],
      original_question_text: attrs["original_question_text"],
      time_ago: attrs["time_ago"],
      timestamp: attrs["timestamp"],
      answers: answers
    }
  end

  @doc """
  Returns the number of answers for this question.

  ## Parameters

  - `question` - A `GoogleQuestion` struct

  ## Returns

  Integer count of answers.

  ## Examples

      iex> question = %DataForSEO.Schemas.GoogleQuestion{answers: [%GoogleAnswer{}, %GoogleAnswer{}]}
      iex> DataForSEO.Schemas.GoogleQuestion.answer_count(question)
      2

  """
  @spec answer_count(t()) :: non_neg_integer()
  def answer_count(%__MODULE__{answers: answers}), do: length(answers)

  @doc """
  Checks if the question has any answers.

  ## Parameters

  - `question` - A `GoogleQuestion` struct

  ## Returns

  Boolean indicating whether the question has answers.

  ## Examples

      iex> question = %DataForSEO.Schemas.GoogleQuestion{answers: [%GoogleAnswer{}]}
      iex> DataForSEO.Schemas.GoogleQuestion.has_answers?(question)
      true

  """
  @spec has_answers?(t()) :: boolean()
  def has_answers?(%__MODULE__{answers: answers}), do: length(answers) > 0
end
