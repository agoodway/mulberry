defmodule Mulberry.Chains.TextClassificationChain do
  @moduledoc """
  A chain for classifying text into predefined categories.

  This chain takes input text and categorizes it into one of the provided categories
  using a language model to analyze the content and determine the best match.

  ## Example

      alias Mulberry.Chains.TextClassificationChain
      alias Mulberry.LangChain.Config
      
      {:ok, llm} = Config.get_llm(:classify)
      
      chain = TextClassificationChain.new!(%{
        llm: llm,
        input_text: "The new iPhone features an improved camera and faster processor...",
        categories: ["Technology", "Business", "Health", "Sports"],
        examples: [
          {"The latest smartphone release", "Technology"},
          {"Company earnings report", "Business"}
        ],
        verbose: true
      })
      
      case TextClassificationChain.evaluate(chain) do
        {:ok, category} -> IO.puts("Classified as: " <> category)
        {:error, reason} -> IO.puts("Failed: " <> inspect(reason))
      end
  """

  use Ecto.Schema
  import Ecto.Changeset
  require Logger
  alias __MODULE__
  alias LangChain.Chains.LLMChain
  alias LangChain.Message

  @primary_key false
  embedded_schema do
    field(:llm, :any, virtual: true)
    field(:input_text, :string)
    field(:categories, {:array, :string}, default: [])
    field(:fallback_category, :string)
    field(:examples, {:array, :any}, default: [])
    field(:override_system_prompt, :string)
    field(:verbose, :boolean, default: false)
    field(:additional_messages, {:array, :any}, default: [], virtual: true)
  end

  @create_fields [
    :llm,
    :input_text,
    :categories,
    :fallback_category,
    :examples,
    :override_system_prompt,
    :verbose,
    :additional_messages
  ]
  @required_fields [:llm, :categories]

  @default_system_prompt ~s|You are a helpful text classifier that categorizes content into predefined categories.

You must classify the given text into EXACTLY ONE of these categories:
<%= for category <- @categories do %>- <%= category %>
<% end %>

<%= if @examples != [] do %>Here are some example classifications:
<%= for {text, category} <- @examples do %>Text: "<%= text %>"
Category: <%= category %>

<% end %><% end %>
Analyze the text carefully and respond with ONLY the category name. Do not include any explanation or additional text.|

  @type t :: %TextClassificationChain{}

  @doc """
  Creates a new TextClassificationChain struct with the given attributes.
  """
  @spec new(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def new(attrs \\ %{}) do
    %TextClassificationChain{}
    |> cast(attrs, @create_fields)
    |> validate_required(@required_fields)
    |> validate_length(:categories, min: 2)
    |> validate_change(:input_text, fn :input_text, value ->
      # Require the field to be present (not nil), but allow empty strings
      if is_nil(value) do
        [input_text: "is required"]
      else
        []
      end
    end)
    |> validate_change(:examples, fn :examples, value ->
      if is_list(value) && Enum.all?(value, &valid_example?/1) do
        []
      else
        [examples: "must be a list of {text, category} tuples"]
      end
    end)
    |> apply_action(:insert)
  end

  @doc """
  Creates a new TextClassificationChain struct with the given attributes, raising on error.
  """
  @spec new!(map()) :: t() | no_return()
  def new!(attrs \\ %{}) do
    case new(attrs) do
      {:ok, chain} -> chain
      {:error, changeset} -> raise "Invalid TextClassificationChain: #{inspect(changeset.errors)}"
    end
  end

  @doc """
  Evaluates the chain to classify the input text into one of the categories.

  Returns `{:ok, category}` on success or `{:error, reason}` on failure.
  """
  @spec evaluate(t(), Keyword.t()) :: {:ok, String.t()} | {:error, any()}
  def evaluate(%TextClassificationChain{} = chain, opts \\ []) do
    if chain.verbose do
      Logger.info(
        "TextClassificationChain evaluating with categories: #{inspect(chain.categories)}"
      )
    end

    result =
      chain
      |> prepare_messages()
      |> run_llm_chain(chain, opts)

    case result do
      {:ok, category} ->
        handle_success(chain, String.trim(category))

      {:error, reason} ->
        handle_error(chain, reason)
    end
  end

  # Handles successful classification result
  @spec handle_success(t(), String.t()) :: {:ok, String.t()} | {:error, any()}
  defp handle_success(chain, category) do
    # Validate that the category is one of the provided categories
    if category in chain.categories do
      if chain.verbose do
        Logger.info("TextClassificationChain classified as: #{inspect(category)}")
      end

      {:ok, category}
    else
      Logger.warning(
        "LLM returned invalid category: #{inspect(category)}. Expected one of: #{inspect(chain.categories)}"
      )

      if chain.fallback_category do
        Logger.info("Using fallback category: #{chain.fallback_category}")
        {:ok, chain.fallback_category}
      else
        {:error, {:invalid_category, category}}
      end
    end
  end

  # Handles classification error
  @spec handle_error(t(), any()) :: {:ok, String.t()} | {:error, any()}
  defp handle_error(chain, reason) do
    Logger.error("TextClassificationChain failed. Reason: #{inspect(reason)}")

    if chain.fallback_category do
      Logger.info("Using fallback category: #{chain.fallback_category}")
      {:ok, chain.fallback_category}
    else
      {:error, reason}
    end
  end

  # Validates example format
  @spec valid_example?(any()) :: boolean()
  defp valid_example?({text, category}) when is_binary(text) and is_binary(category), do: true
  defp valid_example?(_), do: false

  # Prepares the messages for the LLM chain using the prompt template.
  @spec prepare_messages(t()) :: [Message.t()]
  defp prepare_messages(%TextClassificationChain{} = chain) do
    system_prompt = chain.override_system_prompt || @default_system_prompt

    # Prepare template variables
    template_vars = %{
      categories: chain.categories,
      examples: chain.examples
    }

    # Render the system prompt with EEx
    rendered_prompt = EEx.eval_string(system_prompt, assigns: template_vars)

    system_message = Message.new_system!(rendered_prompt)
    user_message = Message.new_user!("Classify the following text:\n\n#{chain.input_text}")

    # Build messages list with additional messages inserted between system and user
    messages = [system_message]
    messages = messages ++ (chain.additional_messages || [])
    messages ++ [user_message]
  end

  # Runs the LLM chain with the prepared messages.
  @spec run_llm_chain([Message.t()], t(), Keyword.t()) :: {:ok, String.t()} | {:error, any()}
  defp run_llm_chain(messages, chain, _opts) do
    verbose = chain.verbose || Application.get_env(:mulberry, :verbose_logging, false)

    %{llm: chain.llm, verbose: verbose}
    |> LLMChain.new!()
    |> LLMChain.add_messages(messages)
    |> LLMChain.run(mode: :while_needs_response)
    |> case do
      {:ok, _updated_chain, response} ->
        extract_content(response)

      {:ok, %LLMChain{last_message: last_message}} when not is_nil(last_message) ->
        # Handle the case where only the chain is returned
        extract_content(last_message)

      {:error, _updated_chain, error} ->
        {:error, error}

      other ->
        {:error, {:unexpected_response, other}}
    end
  end

  defp extract_content(%Message{content: content}) when is_binary(content) do
    {:ok, content}
  end

  defp extract_content(%{content: content}) when is_binary(content) do
    {:ok, content}
  end

  defp extract_content(response) do
    {:error, {:invalid_response_format, response}}
  end
end
