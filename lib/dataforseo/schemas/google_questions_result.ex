defmodule DataForSEO.Schemas.GoogleQuestionsResult do
  @moduledoc """
  Schema representing the result of a Google My Business questions and answers API request.

  Contains collections of questions (both with and without answers) along with metadata
  about the business and query parameters.
  """

  @derive Jason.Encoder

  alias DataForSEO.Schemas.GoogleQuestion

  @type metadata :: %{
          keyword: String.t() | nil,
          se_domain: String.t() | nil,
          location_code: integer() | nil,
          language_code: String.t() | nil,
          check_url: String.t() | nil,
          datetime: String.t() | nil,
          cid: String.t() | nil,
          feature_id: String.t() | nil,
          item_types: [String.t()],
          items_count: integer() | nil
        }

  @type t :: %__MODULE__{
          questions_with_answers: [GoogleQuestion.t()],
          questions_without_answers: [GoogleQuestion.t()],
          metadata: metadata()
        }

  defstruct [
    :metadata,
    questions_with_answers: [],
    questions_without_answers: []
  ]

  @doc """
  Creates a new GoogleQuestionsResult struct from API response attributes.

  ## Parameters

  - `attrs` - Map containing result data from the API response

  ## Returns

  A `GoogleQuestionsResult` struct with questions and metadata populated from the attributes map.

  ## Examples

      iex> attrs = %{
      ...>   "keyword" => "The Last Bookstore",
      ...>   "cid" => "123456",
      ...>   "items" => [
      ...>     %{"question_id" => "1", "question_text" => "Are you open?", "items" => []}
      ...>   ],
      ...>   "items_without_answers" => []
      ...> }
      iex> result = DataForSEO.Schemas.GoogleQuestionsResult.new(attrs)
      iex> result.metadata.keyword
      "The Last Bookstore"

  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    questions_with_answers =
      (attrs["items"] || [])
      |> Enum.map(&GoogleQuestion.new/1)

    questions_without_answers =
      (attrs["items_without_answers"] || [])
      |> Enum.map(&GoogleQuestion.new/1)

    metadata = %{
      keyword: attrs["keyword"],
      se_domain: attrs["se_domain"],
      location_code: attrs["location_code"],
      language_code: attrs["language_code"],
      check_url: attrs["check_url"],
      datetime: attrs["datetime"],
      cid: attrs["cid"],
      feature_id: attrs["feature_id"],
      item_types: attrs["item_types"] || [],
      items_count: attrs["items_count"]
    }

    %__MODULE__{
      questions_with_answers: questions_with_answers,
      questions_without_answers: questions_without_answers,
      metadata: metadata
    }
  end

  @doc """
  Returns the total count of questions (with and without answers).

  ## Parameters

  - `result` - A `GoogleQuestionsResult` struct

  ## Returns

  Integer count of all questions.

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleQuestionsResult{
      ...>   questions_with_answers: [%GoogleQuestion{}, %GoogleQuestion{}],
      ...>   questions_without_answers: [%GoogleQuestion{}]
      ...> }
      iex> DataForSEO.Schemas.GoogleQuestionsResult.total_question_count(result)
      3

  """
  @spec total_question_count(t()) :: non_neg_integer()
  def total_question_count(%__MODULE__{
        questions_with_answers: with_answers,
        questions_without_answers: without_answers
      }) do
    length(with_answers) + length(without_answers)
  end

  @doc """
  Returns all questions (both with and without answers) as a single list.

  ## Parameters

  - `result` - A `GoogleQuestionsResult` struct

  ## Returns

  List of all `GoogleQuestion` structs.

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleQuestionsResult{
      ...>   questions_with_answers: [%GoogleQuestion{question_id: "1"}],
      ...>   questions_without_answers: [%GoogleQuestion{question_id: "2"}]
      ...> }
      iex> all = DataForSEO.Schemas.GoogleQuestionsResult.all_questions(result)
      iex> length(all)
      2

  """
  @spec all_questions(t()) :: [GoogleQuestion.t()]
  def all_questions(%__MODULE__{
        questions_with_answers: with_answers,
        questions_without_answers: without_answers
      }) do
    with_answers ++ without_answers
  end

  @doc """
  Returns the count of questions that have at least one answer.

  ## Parameters

  - `result` - A `GoogleQuestionsResult` struct

  ## Returns

  Integer count of answered questions.

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleQuestionsResult{
      ...>   questions_with_answers: [%GoogleQuestion{}, %GoogleQuestion{}],
      ...>   questions_without_answers: []
      ...> }
      iex> DataForSEO.Schemas.GoogleQuestionsResult.answered_question_count(result)
      2

  """
  @spec answered_question_count(t()) :: non_neg_integer()
  def answered_question_count(%__MODULE__{questions_with_answers: questions}) do
    length(questions)
  end

  @doc """
  Returns the count of questions that have no answers.

  ## Parameters

  - `result` - A `GoogleQuestionsResult` struct

  ## Returns

  Integer count of unanswered questions.

  ## Examples

      iex> result = %DataForSEO.Schemas.GoogleQuestionsResult{
      ...>   questions_with_answers: [],
      ...>   questions_without_answers: [%GoogleQuestion{}]
      ...> }
      iex> DataForSEO.Schemas.GoogleQuestionsResult.unanswered_question_count(result)
      1

  """
  @spec unanswered_question_count(t()) :: non_neg_integer()
  def unanswered_question_count(%__MODULE__{questions_without_answers: questions}) do
    length(questions)
  end
end
