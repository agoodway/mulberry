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
    field :llm, :any, virtual: true
    field :schema, :map
    field :text, :string
    field :system_message, :string
    field :verbose, :boolean, default: false
  end
  
  @type t :: %__MODULE__{}
  
  @default_system_message """
  You are a helpful assistant that extracts structured information from text.
  Extract and save the relevant entities mentioned in the text based on the provided schema.
  If a property is not present or cannot be determined from the text, omit it from the extracted data.
  Return the extracted information as a JSON array, even if only one instance is found.
  If no relevant information is found, return an empty array: []
  """
  
  @doc """
  Runs the data extraction chain with the given language model, schema, and text.
  
  ## Parameters
    - `llm` - The language model to use for extraction
    - `schema` - JSON schema or Function struct defining the data structure to extract
    - `text` - The text to extract data from
    - `opts` - Optional parameters:
      - `:system_message` - Override the default system message
      - `:verbose` - Enable verbose logging (default: false)
  
  ## Returns
    - `{:ok, extracted_data}` - A list of maps containing the extracted data
    - `{:error, reason}` - If extraction fails
  """
  @spec run(any(), map() | Function.t(), String.t(), Keyword.t()) :: 
    {:ok, list(map())} | {:error, any()}
  def run(llm, schema, text, opts \\ []) do
    system_message = Keyword.get(opts, :system_message, @default_system_message)
    verbose = Keyword.get(opts, :verbose, false)
    
    with {:ok, extract_function} <- build_extract_function(schema),
         {:ok, chain} <- build_chain(llm, system_message, extract_function, verbose),
         {:ok, updated_chain} <- LLMChain.run(chain, text: text, mode: :invoke_tools) do
      
      case extract_results(updated_chain) do
        {:ok, results} -> {:ok, results}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
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
  
  defp build_extract_function(schema) when is_map(schema) do
    properties = Map.get(schema, "properties", schema[:properties] || %{})
    required = Map.get(schema, "required", schema[:required] || [])
    
    # Create a simple function definition that will be called by the LLM
    # LangChain expects functions to have arity of 2 (args, context)
    function_def = fn args, _context ->
      # This function won't actually be called in our tests
      # The LLM will invoke it through tool calls
      {:ok, args}
    end
    
    function = Function.new!(%{
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
  
  defp build_extract_function(%Function{} = function) do
    {:ok, function}
  end
  
  defp build_extract_function(_) do
    {:error, "Schema must be a map or Function struct"}
  end
  
  defp build_chain(llm, system_message, extract_function, verbose) do
    messages = [
      Message.new_system!(system_message),
      Message.new_user!("Extract information from the following text:\n\n<%= @text %>")
    ]
    
    chain = %{
      llm: llm,
      messages: messages,
      functions: [extract_function],
      verbose: verbose
    }
    
    LLMChain.new(chain)
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
    when is_list(tool_calls) and tool_calls != [], do: true
  defp assistant_with_tool_calls?(_), do: false

  defp get_first_tool_call(%{tool_calls: [tool_call | _]}), do: {:ok, tool_call}
  defp get_first_tool_call(_), do: {:error, :no_tool_calls}

  defp extract_data_from_tool_call(%{"function" => %{"arguments" => args}}) when is_binary(args) do
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
end