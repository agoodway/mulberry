defmodule Mulberry.Chains.DataExtractionChain do
  @moduledoc """
  A chain for extracting structured data from text using language models.

  This chain takes unstructured text and extracts structured information based on
  a provided JSON schema. It can extract multiple instances of the defined structure
  from a single text passage.

  ## Example

      alias Mulberry.Chains.DataExtractionChain
      alias Mulberry.LangChain.Config
      
      {:ok, llm} = Config.get_llm(:extract)
      
      schema = %{
        type: "object",
        properties: %{
          person_name: %{type: "string"},
          person_age: %{type: "number"},
          occupation: %{type: "string"}
        }
      }
      
      text = "John Smith is a 32-year-old software engineer. 
              Jane Doe, aged 28, works as a data scientist."
      
      case DataExtractionChain.run(llm, schema, text) do
        {:ok, extracted_data} -> 
          # Returns a list of extracted instances:
          # [
          #   %{"person_name" => "John Smith", "person_age" => 32, "occupation" => "software engineer"},
          #   %{"person_name" => "Jane Doe", "person_age" => 28, "occupation" => "data scientist"}
          # ]
        {:error, reason} -> IO.puts("Failed: " <> inspect(reason))
      end
  """

  use Ecto.Schema
  import Ecto.Changeset
  require Logger
  alias LangChain.Chains.LLMChain
  alias LangChain.Message
  alias LangChain.Function

  @primary_key false
  embedded_schema do
    field(:llm, :any, virtual: true)
    field(:schema, :map)
    field(:text, :string)
    field(:system_message, :string)
    field(:verbose, :boolean, default: false)
  end

  @type t :: %__MODULE__{}

  @default_system_message """
  You are a helpful assistant that extracts structured information from text.
  Extract and save the relevant entities mentioned in the text based on the provided schema.
  If a property is not present or cannot be determined from the text, omit it from the extracted data.
  Return the extracted information as a JSON array, even if only one instance is found.
  If no relevant information is found, return an empty array: []
  """

  @default_max_attempts 3
  @default_retry_delay_ms 500

  @doc """
  Runs the data extraction chain with the given language model, schema, and text.

  Supports automatic retry with validation feedback when extraction fails validation.
  By default, validates against the schema's required fields and retries up to 3 times.

  ## Parameters
    - `llm` - The language model to use for extraction
    - `schema` - JSON schema or Function struct defining the data structure to extract
    - `text` - The text to extract data from
    - `opts` - Optional parameters:
      - `:system_message` - Override the default system message
      - `:verbose` - Enable verbose logging (default: false)
      - `:max_attempts` - Maximum extraction attempts (default: 3)
      - `:retry_delay_ms` - Base delay between retries in ms (default: 500)
      - `:validator` - Custom validator function `(results -> {:ok, results} | {:error, errors})`
      - `:validate` - Enable/disable all validation (default: true)

  ## Returns
    - `{:ok, extracted_data}` - A list of maps containing the extracted data
    - `{:error, {:max_attempts_exceeded, attempts, errors}}` - If all attempts fail validation
    - `{:error, reason}` - If extraction fails for other reasons
  """
  @spec run(any(), map() | Function.t(), String.t(), Keyword.t()) ::
          {:ok, list(map())} | {:error, any()}
  def run(llm, schema, text, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, @default_max_attempts)

    if max_attempts <= 1 do
      run_once(llm, schema, text, opts)
    else
      state = %{attempt: 1, max: max_attempts, feedback: [], schema: schema}
      run_with_retry(llm, schema, text, opts, state)
    end
  end

  # Retry logic with validation feedback
  defp run_with_retry(_llm, _schema, _text, _opts, %{
         attempt: attempt,
         max: max,
         feedback: feedback
       })
       when attempt > max do
    {:error, {:max_attempts_exceeded, attempt - 1, feedback}}
  end

  defp run_with_retry(llm, schema, text, opts, state) do
    enhanced_opts = maybe_add_feedback(opts, state.feedback)

    case run_once(llm, schema, text, enhanced_opts) do
      {:ok, results} ->
        case validate_results(results, state.schema, opts) do
          {:ok, validated} ->
            {:ok, validated}

          {:error, validation_errors} ->
            Logger.warning(
              "Extraction attempt #{state.attempt} failed validation: #{inspect(validation_errors)}"
            )

            delay = calculate_delay(opts, state.attempt)
            Process.sleep(delay)

            run_with_retry(llm, schema, text, opts, %{
              state
              | attempt: state.attempt + 1,
                feedback: validation_errors
            })
        end

      {:error, reason} = error ->
        if retryable_error?(reason) and state.attempt < state.max do
          Logger.warning(
            "Extraction attempt #{state.attempt} failed: #{inspect(reason)}, retrying..."
          )

          delay = calculate_delay(opts, state.attempt)
          Process.sleep(delay)
          run_with_retry(llm, schema, text, opts, %{state | attempt: state.attempt + 1})
        else
          error
        end
    end
  end

  # Single extraction attempt (original logic)
  defp run_once(llm, schema, text, opts) do
    system_message = Keyword.get(opts, :system_message, @default_system_message)
    verbose = Keyword.get(opts, :verbose, false)

    with {:ok, extract_function} <- build_extract_function(schema),
         {:ok, chain} <- build_chain(llm, system_message, extract_function, text, verbose) do
      chain
      |> LLMChain.run()
      |> handle_llm_response()
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Handle LLMChain.run/1 response - supports both 2-tuple and 3-tuple formats
  defp handle_llm_response({:ok, updated_chain, _response}), do: extract_results(updated_chain)
  defp handle_llm_response({:ok, updated_chain}), do: extract_results(updated_chain)
  defp handle_llm_response({:error, _updated_chain, reason}), do: {:error, reason}
  defp handle_llm_response({:error, reason}), do: {:error, reason}
  defp handle_llm_response(other), do: {:error, {:unexpected_response, other}}

  @doc """
  Creates a new DataExtractionChain struct with the given attributes.
  """
  @spec new(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def new(attrs \\ %{}) do
    %__MODULE__{}
    |> changeset(attrs)
    |> apply_action(:create)
  end

  @doc """
  Creates a new DataExtractionChain struct with the given attributes, raising on error.
  """
  @spec new!(map()) :: t()
  def new!(attrs \\ %{}) do
    case new(attrs) do
      {:ok, chain} -> chain
      {:error, changeset} -> raise "Invalid DataExtractionChain: #{inspect(changeset)}"
    end
  end

  defp changeset(chain, attrs) do
    chain
    |> cast(attrs, [:llm, :schema, :text, :system_message, :verbose])
    |> validate_required([:llm, :schema, :text])
  end

  defp build_extract_function(%Function{} = function) do
    {:ok, function}
  end

  defp build_extract_function(schema) when is_map(schema) do
    properties = Map.get(schema, "properties", Map.get(schema, :properties, %{}))
    required = Map.get(schema, "required", Map.get(schema, :required, []))

    # Create a simple function definition that will be called by the LLM
    # LangChain expects functions to have arity of 2 (args, context)
    function_def = fn args, _context ->
      # This function won't actually be called in our tests
      # The LLM will invoke it through tool calls
      {:ok, args}
    end

    function =
      Function.new!(%{
        name: "information_extraction",
        description: "Extract structured information from the provided text",
        function: function_def,
        parameters_schema: %{
          type: "object",
          properties: %{
            "data" => %{
              type: "array",
              description: "Array of extracted data instances",
              items: %{
                type: "object",
                properties: properties,
                required: required
              }
            }
          },
          required: ["data"]
        }
      })

    {:ok, function}
  end

  defp build_extract_function(_) do
    {:error, "Schema must be a map or Function struct"}
  end

  defp build_chain(llm, system_message, extract_function, text, verbose) do
    messages = [
      Message.new_system!(system_message),
      Message.new_user!("Extract information from the following text:\n\n#{text}")
    ]

    if verbose do
      Logger.info("Building chain with #{length(messages)} messages")
      Logger.info("Text length: #{String.length(text)} characters")
    end

    chain =
      %{llm: llm, verbose: verbose}
      |> LLMChain.new!()
      |> LLMChain.add_messages(messages)
      |> LLMChain.add_tools([extract_function])

    {:ok, chain}
  end

  defp extract_results(chain) do
    with {:ok, assistant_msg} <- find_assistant_message(chain),
         {:ok, tool_call} <- get_first_tool_call(assistant_msg),
         {:ok, data} <- extract_data_from_tool_call(tool_call) do
      {:ok, data}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:ok, []}
    end
  end

  defp find_assistant_message(%{messages: messages}) when is_list(messages) do
    case Enum.find(messages, &assistant_with_tool_calls?/1) do
      nil -> {:error, :no_assistant_message}
      msg -> {:ok, msg}
    end
  end

  defp find_assistant_message(_), do: {:error, :invalid_chain}

  defp assistant_with_tool_calls?(%{role: :assistant, tool_calls: tool_calls})
       when is_list(tool_calls) and tool_calls != [],
       do: true

  defp assistant_with_tool_calls?(_), do: false

  defp get_first_tool_call(%{tool_calls: [tool_call | _]}), do: {:ok, tool_call}
  defp get_first_tool_call(_), do: {:error, :no_tool_calls}

  defp extract_data_from_tool_call(%{"function" => %{"arguments" => args}})
       when is_binary(args) do
    case Jason.decode(args) do
      {:ok, %{"data" => data}} when is_list(data) -> {:ok, data}
      {:ok, _} -> {:ok, []}
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  defp extract_data_from_tool_call(%{arguments: %{"data" => data}}) when is_list(data) do
    {:ok, data}
  end

  defp extract_data_from_tool_call(_), do: {:ok, []}

  # Validation functions

  defp validate_results(results, schema, opts) do
    if Keyword.get(opts, :validate, true) == false do
      {:ok, results}
    else
      do_validate_results(results, schema, opts)
    end
  end

  defp do_validate_results(results, schema, opts) do
    schema_errors = validate_against_schema(results, schema)
    custom_errors = run_custom_validator(results, opts)
    all_errors = schema_errors ++ custom_errors

    if Enum.empty?(all_errors), do: {:ok, results}, else: {:error, all_errors}
  end

  defp run_custom_validator(results, opts) do
    case Keyword.get(opts, :validator) do
      nil ->
        []

      validator when is_function(validator, 1) ->
        case validator.(results) do
          {:ok, _} -> []
          {:error, errors} when is_list(errors) -> errors
          {:error, error} -> [to_string(error)]
        end
    end
  end

  defp validate_against_schema(results, schema) when is_list(results) do
    required = get_required_fields(schema)

    results
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, index} ->
      item_keys = Map.keys(item) |> Enum.map(&to_string/1)
      missing = required -- item_keys

      if Enum.empty?(missing) do
        []
      else
        ["Item #{index}: missing required fields: #{Enum.join(missing, ", ")}"]
      end
    end)
  end

  defp validate_against_schema(_results, _schema), do: []

  defp get_required_fields(schema) do
    Map.get(schema, :required, Map.get(schema, "required", []))
    |> Enum.map(&to_string/1)
  end

  # Feedback enhancement

  defp maybe_add_feedback(opts, []), do: opts

  defp maybe_add_feedback(opts, feedback) do
    base_message = Keyword.get(opts, :system_message, @default_system_message)

    feedback_text = """

    IMPORTANT: Your previous extraction had validation errors. Please fix them:
    #{Enum.map_join(feedback, "\n", fn err -> "- #{err}" end)}

    Ensure all required fields are present and properly formatted.
    """

    Keyword.put(opts, :system_message, base_message <> feedback_text)
  end

  # Retry helpers

  defp calculate_delay(opts, attempt) do
    base = Keyword.get(opts, :retry_delay_ms, @default_retry_delay_ms)
    round(base * :math.pow(2, attempt - 1))
  end

  defp retryable_error?({:json_decode_error, _}), do: true
  defp retryable_error?(:no_assistant_message), do: true
  defp retryable_error?(:no_tool_calls), do: true
  defp retryable_error?(_), do: false
end
