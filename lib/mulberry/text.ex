defmodule Mulberry.Text do
  @moduledoc false

  alias LangChain.Chains.LLMChain
  alias LangChain.Message
  alias Mulberry.LangChain.Config
  alias Mulberry.Chains.TextToTitleChain
  alias TextChunker.Chunk

  @doc """
  Splits text into semantic chunks for processing.

  Returns a list of text chunks as strings for simple usage,
  or {:ok, chunks} with full chunk data when needed.
  """
  @spec split(String.t()) :: [String.t()] | {:ok, [Chunk.t()]} | {:error, String.t()}
  def split(text) when is_binary(text) do
    chunks =
      text
      |> TextChunker.split()
      |> Enum.map(fn chunk ->
        %{chunk | text: String.replace(chunk.text, "\n", " ")}
      end)

    # Return just the text strings for backward compatibility
    Enum.map(chunks, & &1.text)
  end

  def split(_) do
    {:error, "You must pass a string to Mulberry.Text.split/1"}
  end

  @doc """
  Tokenizes text into individual tokens using a BERT tokenizer.
  """
  @spec tokens(String.t()) :: {:ok, [String.t()]} | {:error, atom()}
  def tokens(text) do
    with {:ok, tokenizer} <- Tokenizers.Tokenizer.from_pretrained("bert-base-cased"),
         {:ok, encoding} <- Tokenizers.Tokenizer.encode(tokenizer, text) do
      {:ok, Tokenizers.Encoding.get_tokens(encoding)}
    else
      _ ->
        {:error, :tokenization_failed}
    end
  end

  @doc """
  Counts the number of tokens in the given text.
  """
  @spec token_count(String.t()) :: {:ok, pos_integer()} | {:error, atom()}
  def token_count(text) do
    text
    |> tokens()
    |> case do
      {:ok, tokens} -> {:ok, Enum.count(tokens)}
      error -> error
    end
  end

  @doc """
  Generates a summary of the text using a language model with advanced chunking strategies.

  ## Options
    * `:provider` - The LLM provider to use (e.g., :openai, :anthropic, :google)
    * `:model` - Override the default model for the provider
    * `:temperature` - Override the temperature setting
    * `:max_tokens` - Override the max tokens setting
    * `:api_key` - Override the API key
    * `:system_message` - Custom system message to override the default
    * `:llm` - A pre-configured LLM instance (for backward compatibility)
    * `:verbose` - Enable verbose logging for debugging (default: false)
    * `:strategy` - Summarization strategy (:stuff, :map_reduce, or :refine). Defaults to :stuff
    * `:chunk_size` - Size of text chunks for processing (default: 1000)
    * `:chunk_overlap` - Overlap between chunks (default: 200)
    * `:max_chunks_per_group` - For map_reduce strategy (default: 10)
    * `:on_progress` - Progress callback function with signature fn(stage, info) -> any()
    * `:with_fallbacks` - List of fallback LLMs to use if primary fails
  """
  @spec summarize(String.t(), Keyword.t()) :: {:ok, String.t()} | {:error, any()}
  def summarize(text, opts \\ []) do
    alias Mulberry.Chains.SummarizeDocumentChain

    # Get LLM configuration
    llm =
      case Keyword.get(opts, :llm) do
        nil ->
          # Use new configuration system
          case Config.get_llm(:summarize, opts) do
            {:ok, llm} -> llm
            {:error, reason} -> raise "Failed to create LLM: #{inspect(reason)}"
          end

        llm ->
          # Use provided LLM instance for backward compatibility
          llm
      end

    # Extract chain configuration
    strategy = Keyword.get(opts, :strategy, :stuff)
    chunk_size = Keyword.get(opts, :chunk_size, 1000)
    chunk_overlap = Keyword.get(opts, :chunk_overlap, 200)
    max_chunks_per_group = Keyword.get(opts, :max_chunks_per_group, 10)
    verbose = Keyword.get(opts, :verbose, false)

    # Handle custom prompts
    system_message = Keyword.get(opts, :system_message)

    chain_config = %{
      llm: llm,
      strategy: strategy,
      chunk_size: chunk_size,
      chunk_overlap: chunk_overlap,
      max_chunks_per_group: max_chunks_per_group,
      verbose: verbose
    }

    # Add custom prompts if provided
    chain_config =
      if system_message do
        # For backward compatibility, use the system message as the summarize prompt
        Map.put(chain_config, :summarize_prompt, system_message)
      else
        chain_config
      end

    # Create and run the summarization chain
    case SummarizeDocumentChain.new(chain_config) do
      {:ok, chain} ->
        # Extract options for the summarize call
        summarize_opts = Keyword.take(opts, [:on_progress, :with_fallbacks])

        # Create a simple document-like structure for the chain
        doc = %{text: text}

        SummarizeDocumentChain.summarize(chain, doc, summarize_opts)

      {:error, changeset} ->
        {:error, "Failed to create summarization chain: #{inspect(changeset)}"}
    end
  end

  @doc """
  Generates a concise title (max 14 words) for the given text.

  ## Options
    * `:provider` - The LLM provider to use (e.g., :openai, :anthropic, :google)
    * `:model` - Override the default model for the provider
    * `:temperature` - Override the temperature setting
    * `:max_tokens` - Override the max tokens setting
    * `:api_key` - Override the API key
    * `:system_message` - Custom system message to override the default
    * `:additional_messages` - Additional messages to include in the conversation
    * `:llm` - A pre-configured LLM instance (for backward compatibility)
    * `:llm_config` - Legacy configuration options (for backward compatibility)
    * `:verbose` - Enable verbose logging for debugging (default: false)
    * `:examples` - List of example titles to guide the style
    * `:fallback_title` - Title to use if generation fails (default: "Untitled")
    * `:max_words` - Maximum number of words in the title (default: 14)
  """
  @spec title(String.t(), Keyword.t()) :: {:ok, String.t()} | {:error, any()}
  def title(text, opts \\ []) do
    # Backward compatibility: check if :llm is provided
    llm =
      case Keyword.get(opts, :llm) do
        nil ->
          # Use new configuration system
          case Config.get_llm(:title, opts) do
            {:ok, llm} -> llm
            {:error, reason} -> raise "Failed to create LLM: #{inspect(reason)}"
          end

        llm ->
          # Use provided LLM instance for backward compatibility
          llm
      end

    default_system_message = """
    You are a helpful copy writer.
    Please analyze the content and generate a title that is no more than 14 words.
    Before generating a title from the content, consider the following:
    - Identify the main themes, topics, or ideas discussed in the content.
    - Recognize important facts, figures, or examples that support the main points.
    - Capture any essential context or background information necessary for understanding the content.
    - Use clear and concise language to convey the content effectively using an unbiased and journalistic tone.
    - Do not start the title with "Title:"
    """

    system_message = Keyword.get(opts, :system_message, default_system_message)
    additional_messages = Keyword.get(opts, :additional_messages, [])

    messages =
      [Message.new_system!(system_message)] ++
        additional_messages ++
        [Message.new_user!("content: #{text}")]

    verbose = Keyword.get(opts, :verbose, false)

    case run_chain(llm, messages, verbose) do
      {:ok, summary} -> {:ok, summary}
      error -> {:error, error}
    end
    |> TextToTitleChain.new!()
    |> TextToTitleChain.evaluate()
  end

  defp run_chain(llm, messages, verbose) do
    # Get verbose setting from application config if not explicitly passed
    verbose = verbose || Application.get_env(:mulberry, :verbose_logging, false)

    %{llm: llm, verbose: verbose}
    |> LLMChain.new!()
    |> LLMChain.add_messages(messages)
    |> LLMChain.run(mode: :while_needs_response)
    |> case do
      {:ok, _chain, response} ->
        # Handle the response - it might be a Message or a map
        case response do
          %{content: content} when is_binary(content) ->
            {:ok, content}

          %LangChain.Message{content: content} when is_binary(content) ->
            {:ok, content}

          _ ->
            {:error, "No content in response"}
        end

      {:error, _chain, error} ->
        {:error, error}

      error ->
        {:error, error}
    end
  end
end
