defmodule Mulberry.Text do
  @moduledoc false

  alias LangChain.Chains.LLMChain
  alias LangChain.Message
  alias Mulberry.LangChain.Config
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
  Generates a summary of the text using a language model.

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
  """
  @spec summarize(String.t(), Keyword.t()) :: {:ok, String.t()} | {:error, any()}
  def summarize(text, opts \\ []) do
    # Backward compatibility: check if :llm is provided
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

    default_system_message = """
    You are a helpful file contents extractor and summarizer.
    Please analyze the following file content and extract the key meanings into a summary without losing any important information and extract the structured contents without modifying its format.
    Before summarizing the content, consider the following:
    - Ignore any content that is empty, or contain only whitespace characters.
    Summary:
    - Identify the main themes, topics, or ideas discussed in the content.
    - Recognize important facts, figures, or examples that support the main points.
    - Capture any essential context or background information necessary for understanding the content.
    - Avoid repetition and eliminate any redundant or less critical information.
    - Organize the summary by grouping related meanings together under relevant headings or sections.
    - Don't return any promotional or irrelevant information.
    - Use clear and concise language to convey the content effectively using an unbiased and journalistic tone.
    contents:
    - Identify and extract tables, lists, code snippets, or any other formatted contents present in the content.
    - Maintain the original structure and formatting of the extracted contents.
    - Ensure that no information is lost or altered during the extraction process.
    - If there are multiple instances of structured contents, extract each instance separately.
    Please provide your response in well structured contents format. But don't mention "contents" in your response.
    """

    system_message = Keyword.get(opts, :system_message, default_system_message)
    additional_messages = Keyword.get(opts, :additional_messages, [])

    messages = 
      [Message.new_system!(system_message)] ++
      additional_messages ++
      [Message.new_user!("""
      ## text to summarize:
      #{text}
      """)]

    case run_chain(llm, messages) do
      {:ok, summary} -> {:ok, summary}
      error -> {:error, error}
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

    case run_chain(llm, messages) do
      {:ok, summary} -> {:ok, summary}
      error -> {:error, error}
    end
  end

  defp run_chain(llm, messages) do
    %{llm: llm, verbose: false}
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
