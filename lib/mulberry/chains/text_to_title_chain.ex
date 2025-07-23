defmodule Mulberry.Chains.TextToTitleChain do
  @moduledoc """
  A chain for converting text content into concise titles.
  
  This chain takes input text and generates a title that captures the essence
  of the content in a specified number of words or less.
  
  ## Example
  
      alias Mulberry.Chains.TextToTitleChain
      alias Mulberry.LangChain.Config
      
      {:ok, llm} = Config.get_llm(:title)
      
      chain = TextToTitleChain.new!(%{
        llm: llm,
        input_text: "This is a long article about the benefits of elixir programming...",
        max_words: 10,
        examples: ["Elixir Programming Benefits", "Why Choose Elixir"],
        verbose: true
      })
      
      case TextToTitleChain.evaluate(chain) do
        {:ok, title_text} -> IO.puts("Generated title: " <> title_text)
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
    field :llm, :any, virtual: true
    field :input_text, :string
    field :fallback_title, :string, default: "Untitled"
    field :examples, {:array, :string}, default: []
    field :max_words, :integer, default: 14
    field :override_system_prompt, :string
    field :verbose, :boolean, default: false
    field :additional_messages, {:array, :any}, default: [], virtual: true
  end
  
  @create_fields [
    :llm,
    :input_text,
    :fallback_title,
    :examples,
    :max_words,
    :override_system_prompt,
    :verbose,
    :additional_messages
  ]
  @required_fields [:llm]
  
  @default_system_prompt ~s|You are a helpful copy writer who creates concise titles.

<%= if @max_words > 0 do %>Generate a title that is no more than <%= @max_words %> words.<% end %>

Before generating a title from the content, consider the following:
- Identify the main themes, topics, or ideas discussed in the content
- Recognize important facts, figures, or examples that support the main points
- Capture any essential context or background information
- Use clear and concise language with an unbiased and journalistic tone
- Do not start the title with "Title:" or use quotation marks

<%= if @examples != [] do %>Follow the style and format of these example titles:
<%= for example <- @examples do %>- <%= example %>
<% end %><% end %>|
  
  @type t :: %TextToTitleChain{}
  
  @doc """
  Creates a new TextToTitleChain struct with the given attributes.
  """
  @spec new(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def new(attrs \\ %{}) do
    %TextToTitleChain{}
    |> cast(attrs, @create_fields)
    |> validate_required(@required_fields)
    |> validate_number(:max_words, greater_than_or_equal_to: 0)
    |> validate_change(:input_text, fn :input_text, value ->
      # Require the field to be present (not nil), but allow empty strings
      if is_nil(value) do
        [input_text: "is required"]
      else
        []
      end
    end)
    |> apply_action(:insert)
  end
  
  @doc """
  Creates a new TextToTitleChain struct with the given attributes, raising on error.
  """
  @spec new!(map()) :: t() | no_return()
  def new!(attrs \\ %{}) do
    case new(attrs) do
      {:ok, chain} -> chain
      {:error, changeset} -> raise "Invalid TextToTitleChain: #{inspect(changeset.errors)}"
    end
  end
  
  @doc """
  Evaluates the chain to generate a title from the input text.
  
  Returns `{:ok, title}` on success or `{:error, reason}` on failure.
  """
  @spec evaluate(t(), Keyword.t()) :: {:ok, String.t()} | {:error, any()}
  def evaluate(%TextToTitleChain{} = chain, opts \\ []) do
    if chain.verbose do
      Logger.info("TextToTitleChain evaluating with max_words: #{chain.max_words}")
    end
    
    result = 
      chain
      |> prepare_messages()
      |> run_llm_chain(chain, opts)
    
    case result do
      {:ok, title} ->
        title = String.trim(title)
        
        if chain.verbose do
          Logger.info("TextToTitleChain generated: #{inspect(title)}")
        end
        
        {:ok, title}
        
      {:error, reason} ->
        Logger.error("TextToTitleChain failed. Reason: #{inspect(reason)}")
        
        if chain.fallback_title do
          Logger.info("Using fallback title: #{chain.fallback_title}")
          {:ok, chain.fallback_title}
        else
          {:error, reason}
        end
    end
  end
  
  # Prepares the messages for the LLM chain using the prompt template.
  @spec prepare_messages(t()) :: [Message.t()]
  defp prepare_messages(%TextToTitleChain{} = chain) do
    system_prompt = chain.override_system_prompt || @default_system_prompt
    
    # Prepare template variables
    template_vars = %{
      examples: chain.examples,
      max_words: chain.max_words
    }
    
    # Render the system prompt with EEx
    rendered_prompt = EEx.eval_string(system_prompt, assigns: template_vars)
    
    system_message = Message.new_system!(rendered_prompt)
    user_message = Message.new_user!("Generate a title for the following content:\n\n#{chain.input_text}")
    
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