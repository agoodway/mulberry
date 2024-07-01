defmodule Mulberry.Text do
  @moduledoc false
  import Flamel.Wrap, only: [ok: 1]

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.Message
  alias TextChunker.Chunk

  @spec split(String.t()) :: {:ok, [Chunk.t()]} | {:error, String.t()}
  def split(text) when is_binary(text) do
    text
    |> TextChunker.split()
    |> Enum.reduce([], fn chunk, acc ->
      [Map.put(chunk, :text, String.replace(chunk.text, "\n", " ")) | acc]
    end)
    |> Enum.reverse()
    |> ok()
  end

  def split(_) do
    {:error, "You must pass a string to Mulberry.Text.split/1"}
  end

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

  @spec token_count(String.t()) :: {:ok, pos_integer()} | {:error, atom()}
  def token_count(text) do
    text
    |> tokens()
    |> then(fn
      {:ok, tokens} -> Enum.count(tokens)
      _ -> {:error, :tokenization_failed}
    end)
  end

  @spec summarize(String.t(), Keyword.t()) :: {:ok, String.t()} | {:error, any()}
  def summarize(text, _opts \\ []) do
    # TODO: Support opts for diff llms and passing messages
    llm = ChatOpenAI.new!()

    system_message = """
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

    messages = [
      Message.new_system!(system_message),
      Message.new_user!("""
      ## text to summarize:
      #{text}
      """)
    ]

    case run_chain(llm, messages) do
      {:ok, summary} -> {:ok, summary}
      error -> {:error, error}
    end
  end

  @spec title(String.t(), Keyword.t()) :: {:ok, String.t()} | {:error, any()}
  def title(text, _opts \\ []) do
    # TODO: Support opts for diff llms and passing messages
    llm = ChatOpenAI.new!()

    system_message = """
    You are a helpful copy writer.
    Please analyze the content and generate a title that is no more than 14 words.
    Before generating a title from the content, consider the following:
    - Identify the main themes, topics, or ideas discussed in the content.
    - Recognize important facts, figures, or examples that support the main points.
    - Capture any essential context or background information necessary for understanding the content.
    - Use clear and concise language to convey the content effectively using an unbiased and journalistic tone.
    - Do not start the title with "Title:"
    """

    messages = [
      Message.new_system!(system_message),
      Message.new_user!("content: #{text}")
    ]

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
      {:ok, _chain, %{content: content}} ->
        {:ok, content}

      error ->
        error
    end
  end
end
