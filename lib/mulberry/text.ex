defmodule Mulberry.Text do
  @moduledoc """
  Provides text processing functionality including splitting, tokenization, summarization, 
  title generation, and classification using language models.
  
  This module offers various text manipulation and analysis functions that leverage
  AI capabilities through configurable language model providers.
  """

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

    # Build chain attributes
    chain_attrs = %{
      llm: llm,
      input_text: text,
      verbose: Keyword.get(opts, :verbose, false),
      examples: Keyword.get(opts, :examples, []),
      fallback_title: Keyword.get(opts, :fallback_title, "Untitled"),
      max_words: Keyword.get(opts, :max_words, 14),
      additional_messages: Keyword.get(opts, :additional_messages, [])
    }
    
    # Handle custom system message if provided
    chain_attrs = if system_message = Keyword.get(opts, :system_message) do
      Map.put(chain_attrs, :override_system_prompt, system_message)
    else
      chain_attrs
    end

    chain_attrs
    |> TextToTitleChain.new!()
    |> TextToTitleChain.evaluate()
  end

  @doc """
  Classifies text into one of the provided categories using a language model.

  ## Options
    * `:categories` - List of categories to classify into (required)
    * `:provider` - The LLM provider to use (e.g., :openai, :anthropic, :google)
    * `:model` - Override the default model for the provider
    * `:temperature` - Override the temperature setting
    * `:max_tokens` - Override the max tokens setting
    * `:api_key` - Override the API key
    * `:system_message` - Custom system message to override the default
    * `:additional_messages` - Additional messages to include in the conversation
    * `:llm` - A pre-configured LLM instance (for backward compatibility)
    * `:verbose` - Enable verbose logging for debugging (default: false)
    * `:examples` - List of {text, category} tuples to guide classification
    * `:fallback_category` - Category to use if classification fails

  ## Examples

      # Basic classification
      {:ok, category} = Mulberry.Text.classify("The new iPhone features...", 
        categories: ["Technology", "Business", "Health"])
      
      # With examples for few-shot learning
      {:ok, category} = Mulberry.Text.classify("Quarterly earnings report...", 
        categories: ["Technology", "Business", "Health"],
        examples: [
          {"Stock market update", "Business"}, 
          {"New CPU released", "Technology"}
        ])
      
      # With fallback category
      {:ok, category} = Mulberry.Text.classify("Some ambiguous text", 
        categories: ["A", "B", "C"],
        fallback_category: "Unknown")
  """
  @spec classify(String.t(), Keyword.t()) :: {:ok, String.t()} | {:error, any()}
  def classify(text, opts \\ []) do
    alias Mulberry.Chains.TextClassificationChain

    # Ensure categories are provided
    categories = Keyword.get(opts, :categories, [])
    if categories == [] do
      raise ArgumentError, "You must provide :categories option with at least 2 categories"
    end

    # Backward compatibility: check if :llm is provided
    llm =
      case Keyword.get(opts, :llm) do
        nil ->
          # Use new configuration system
          case Config.get_llm(:classify, opts) do
            {:ok, llm} -> llm
            {:error, reason} -> raise "Failed to create LLM: #{inspect(reason)}"
          end

        llm ->
          # Use provided LLM instance for backward compatibility
          llm
      end

    # Build chain attributes
    chain_attrs = %{
      llm: llm,
      input_text: text,
      categories: categories,
      verbose: Keyword.get(opts, :verbose, false),
      examples: Keyword.get(opts, :examples, []),
      fallback_category: Keyword.get(opts, :fallback_category),
      additional_messages: Keyword.get(opts, :additional_messages, [])
    }
    
    # Handle custom system message if provided
    chain_attrs = if system_message = Keyword.get(opts, :system_message) do
      Map.put(chain_attrs, :override_system_prompt, system_message)
    else
      chain_attrs
    end

    chain_attrs
    |> TextClassificationChain.new!()
    |> TextClassificationChain.evaluate()
  end

  @doc """
  Extracts structured data from text using a language model based on a provided schema.

  ## Options
    * `:schema` - JSON schema defining the structure to extract (required)
    * `:provider` - The LLM provider to use (e.g., :openai, :anthropic, :google)
    * `:model` - Override the default model for the provider
    * `:temperature` - Override the temperature setting
    * `:max_tokens` - Override the max tokens setting
    * `:api_key` - Override the API key
    * `:system_message` - Custom system message to override the default
    * `:llm` - A pre-configured LLM instance (for backward compatibility)
    * `:verbose` - Enable verbose logging for debugging (default: false)

  ## Examples

      # Extract person information
      schema = %{
        type: "object",
        properties: %{
          person_name: %{type: "string"},
          person_age: %{type: "number"},
          occupation: %{type: "string"}
        }
      }
      
      text = "John Smith is a 32-year-old software engineer."
      
      {:ok, data} = Mulberry.Text.extract(text, schema: schema)
      # Returns: [%{"person_name" => "John Smith", "person_age" => 32, "occupation" => "software engineer"}]
      
      # Extract multiple instances
      text = "John is 30 and works as a teacher. Jane is 25 and is a doctor."
      {:ok, data} = Mulberry.Text.extract(text, schema: schema)
      # Returns multiple extracted instances
  """
  @spec extract(String.t(), Keyword.t()) :: {:ok, list(map())} | {:error, any()}
  def extract(text, opts \\ []) do
    alias Mulberry.Chains.DataExtractionChain

    # Ensure schema is provided
    schema = Keyword.get(opts, :schema)
    if is_nil(schema) do
      raise ArgumentError, "You must provide :schema option defining the data structure to extract"
    end

    # Get LLM configuration
    llm =
      case Keyword.get(opts, :llm) do
        nil ->
          # Use new configuration system
          case Config.get_llm(:extract, opts) do
            {:ok, llm} -> llm
            {:error, reason} -> raise "Failed to create LLM: #{inspect(reason)}"
          end

        llm ->
          # Use provided LLM instance for backward compatibility
          llm
      end

    # Extract options for the chain
    chain_opts = [
      system_message: Keyword.get(opts, :system_message),
      verbose: Keyword.get(opts, :verbose, false)
    ]
    |> Enum.filter(fn {_k, v} -> v != nil end)

    DataExtractionChain.run(llm, schema, text, chain_opts)
  end
end
