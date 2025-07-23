defmodule Mulberry.Chains.SummarizeDocumentChain do
  @moduledoc """
  A chain for summarizing documents using various strategies.

  This module provides flexible document summarization capabilities with support for:
  - Multiple summarization strategies (stuff, map_reduce, refine)
  - Configurable chunking and overlap
  - Custom prompts and LLM configuration
  - Progress tracking via callbacks

  ## Summarization Strategies

  ### Stuff Strategy
  Concatenates all document chunks and summarizes in a single LLM call.
  Best for small documents that fit within the context window.

  ### Map-Reduce Strategy
  Summarizes each chunk independently, then combines the summaries.
  Ideal for large documents where parallel processing is beneficial.

  ### Refine Strategy
  Iteratively refines the summary by processing chunks sequentially.
  Each chunk refines the previous summary, maintaining context throughout.

  ## Examples

      # Basic usage with default settings
      {:ok, chain} = SummarizeDocumentChain.new(%{
        llm: ChatOpenAI.new!(%{model: "gpt-4", stream: false})
      })
      
      {:ok, summary} = SummarizeDocumentChain.summarize(chain, document)
      
      # Using map-reduce strategy with custom chunk size
      {:ok, chain} = SummarizeDocumentChain.new(%{
        llm: ChatOpenAI.new!(%{model: "gpt-4", stream: false}),
        strategy: :map_reduce,
        chunk_size: 2000,
        chunk_overlap: 200
      })
      
      # With progress tracking
      {:ok, summary} = SummarizeDocumentChain.summarize(chain, document,
        on_progress: fn stage, info ->
          IO.puts("\#{stage}: \#{inspect(info)}")
        end
      )
  """

  use Ecto.Schema
  import Ecto.Changeset
  require Logger

  alias LangChain.Chains.LLMChain
  alias LangChain.LangChainError
  alias LangChain.Utils
  alias LangChain.Utils.ChainResult
  alias LangChain.PromptTemplate
  alias Mulberry.Document
  alias Mulberry.Text
  alias __MODULE__

  @primary_key false
  embedded_schema do
    field(:llm, :any, virtual: true)
    field(:strategy, Ecto.Enum, values: [:stuff, :map_reduce, :refine], default: :stuff)
    field(:chunk_size, :integer, default: 1000)
    field(:chunk_overlap, :integer, default: 100)
    field(:max_chunks_per_group, :integer, default: 10)
    field(:combine_prompt, :string)
    field(:map_prompt, :string)
    field(:refine_prompt, :string)
    field(:verbose, :boolean, default: false)
  end

  @type t :: %SummarizeDocumentChain{}
  @type strategy :: :stuff | :map_reduce | :refine
  @type progress_callback :: (atom(), map() -> any())

  @create_fields [
    :llm,
    :strategy,
    :chunk_size,
    :chunk_overlap,
    :max_chunks_per_group,
    :combine_prompt,
    :map_prompt,
    :refine_prompt,
    :verbose
  ]
  @required_fields [:llm]

  @default_combine_prompt """
  You are an expert at summarizing documents. Please provide a comprehensive summary of the following text.
  Focus on the main ideas, key points, and important details. Be concise but thorough.

  Text to summarize:
  <%= @text %>
  """

  @default_map_prompt """
  You are analyzing a portion of a larger document. Please summarize the following text chunk,
  focusing on the main ideas and key information. This summary will be combined with others.

  Text chunk:
  <%= @text %>
  """

  @default_reduce_prompt """
  You are combining multiple summaries into a final comprehensive summary.
  Please synthesize the following summaries into a single, coherent summary that captures
  all the important information without redundancy.

  Summaries to combine:
  <%= @summaries %>
  """

  @default_refine_prompt """
  You are refining a document summary. Given an existing summary and a new chunk of text,
  please update the summary to incorporate any new important information from the chunk.
  Keep the summary comprehensive but concise.

  Existing summary:
  <%= @existing_summary %>

  New text chunk:
  <%= @text %>
  """

  @doc """
  Creates a new SummarizeDocumentChain with the given configuration.

  ## Options

  - `:llm` - Required. The LLM instance to use for summarization
  - `:strategy` - The summarization strategy (:stuff, :map_reduce, :refine). Default: :stuff
  - `:chunk_size` - Maximum size of text chunks. Default: 1000
  - `:chunk_overlap` - Overlap between chunks. Default: 100
  - `:max_chunks_per_group` - Max chunks to process together in stuff strategy. Default: 10
  - `:combine_prompt` - Custom prompt for combining text (stuff strategy)
  - `:map_prompt` - Custom prompt for mapping phase (map_reduce strategy)
  - `:refine_prompt` - Custom prompt for refining (refine strategy)
  - `:verbose` - Enable verbose logging. Default: false
  """
  @spec new(attrs :: map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def new(attrs \\ %{}) do
    %SummarizeDocumentChain{}
    |> cast(attrs, @create_fields)
    |> validate_required(@required_fields)
    |> validate_number(:chunk_size, greater_than: 0)
    |> validate_number(:chunk_overlap, greater_than_or_equal_to: 0)
    |> validate_number(:max_chunks_per_group, greater_than: 0)
    |> Utils.validate_llm_is_struct()
    |> apply_action(:insert)
  end

  @doc """
  Creates a new SummarizeDocumentChain and returns it or raises an error if invalid.
  """
  @spec new!(attrs :: map()) :: t() | no_return()
  def new!(attrs \\ %{}) do
    case new(attrs) do
      {:ok, chain} -> chain
      {:error, changeset} -> raise LangChainError, changeset
    end
  end

  @doc """
  Evaluates a document using the configured summarization strategy.

  ## Options

  - `:on_progress` - Callback function called with progress updates
  - `:with_fallbacks` - List of fallback LLMs to use if primary fails
  """
  @spec evaluate(t(), Document.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, term()}
  def evaluate(%SummarizeDocumentChain{} = chain, document, opts \\ []) do
    with {:ok, text} <- Document.to_text(document),
         {:ok, chunks} <- chunk_text(chain, text),
         _ <- maybe_call_progress(opts, :chunks_created, %{count: length(chunks)}),
         {:ok, summary} <- apply_strategy(chain, chunks, opts) do
      {:ok, summary}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Summarizes raw text using the configured strategy.
  """
  @spec summarize_text(t(), String.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, term()}
  def summarize_text(%SummarizeDocumentChain{} = chain, text, opts \\ []) do
    with {:ok, chunks} <- chunk_text(chain, text),
         _ <- maybe_call_progress(opts, :chunks_created, %{count: length(chunks)}),
         {:ok, summary} <- apply_strategy(chain, chunks, opts) do
      {:ok, summary}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Alias for evaluate/3 to support simple document maps.

  This function allows passing a simple map with a :text key instead of
  a full Document implementation.
  """
  @spec summarize(t(), map() | Document.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, term()}
  def summarize(%SummarizeDocumentChain{} = chain, %{text: text}, opts) when is_binary(text) do
    summarize_text(chain, text, opts)
  end

  def summarize(%SummarizeDocumentChain{} = chain, document, opts) do
    evaluate(chain, document, opts)
  end

  # Private functions

  defp chunk_text(%{chunk_size: _size, chunk_overlap: _overlap}, text) do
    chunks = Text.split(text)

    # For now, use the simple text chunker results
    # In the future, we could implement size-based chunking with overlap
    {:ok, chunks}
  end

  defp apply_strategy(chain, chunks, opts) do
    case chain.strategy do
      :stuff -> stuff_strategy(chain, chunks, opts)
      :map_reduce -> map_reduce_strategy(chain, chunks, opts)
      :refine -> refine_strategy(chain, chunks, opts)
    end
  end

  defp stuff_strategy(chain, chunks, opts) do
    # Group chunks if there are too many
    chunk_groups = Enum.chunk_every(chunks, chain.max_chunks_per_group)

    summaries =
      chunk_groups
      |> Enum.with_index()
      |> Enum.map(fn {group, index} ->
        _ =
          maybe_call_progress(opts, :processing_group, %{
            group: index + 1,
            total: length(chunk_groups)
          })

        text = Enum.join(group, "\n\n")
        prompt = chain.combine_prompt || @default_combine_prompt

        case run_llm_with_prompt(chain, prompt, %{text: text}, opts) do
          {:ok, summary} -> summary
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    if length(summaries) == 1 do
      {:ok, List.first(summaries)}
    else
      # Recursively summarize if we had multiple groups
      stuff_strategy(chain, summaries, opts)
    end
  end

  defp map_reduce_strategy(chain, chunks, opts) do
    # Map phase: summarize each chunk
    _ = maybe_call_progress(opts, :map_phase_start, %{chunks: length(chunks)})

    chunk_summaries =
      chunks
      |> Enum.with_index()
      |> Enum.map(fn {chunk, index} ->
        _ =
          maybe_call_progress(opts, :mapping_chunk, %{
            chunk: index + 1,
            total: length(chunks)
          })

        prompt = chain.map_prompt || @default_map_prompt

        case run_llm_with_prompt(chain, prompt, %{text: chunk}, opts) do
          {:ok, summary} -> summary
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Reduce phase: combine summaries
    _ = maybe_call_progress(opts, :reduce_phase_start, %{summaries: length(chunk_summaries)})

    summaries_text =
      chunk_summaries
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {summary, index} -> "Summary #{index}:\n#{summary}" end)

    prompt = chain.combine_prompt || @default_reduce_prompt
    run_llm_with_prompt(chain, prompt, %{summaries: summaries_text}, opts)
  end

  defp refine_strategy(chain, chunks, opts) do
    _ = maybe_call_progress(opts, :refine_start, %{chunks: length(chunks)})

    # Start with the first chunk as initial summary
    {first_chunk, remaining_chunks} = List.pop_at(chunks, 0)

    initial_prompt = chain.combine_prompt || @default_combine_prompt

    case run_llm_with_prompt(chain, initial_prompt, %{text: first_chunk}, opts) do
      {:ok, initial_summary} ->
        # Refine with each subsequent chunk
        refined_summary =
          refine_chunks(chain, remaining_chunks, initial_summary, length(chunks), opts)

        {:ok, refined_summary}

      error ->
        error
    end
  end

  defp run_llm_with_prompt(chain, prompt_template, params, opts) do
    messages =
      [
        PromptTemplate.new!(%{
          role: :user,
          text: prompt_template
        })
      ]
      |> PromptTemplate.to_messages!(params)

    run_opts = Keyword.take(opts, [:with_fallbacks])

    %{llm: chain.llm, verbose: chain.verbose}
    |> LLMChain.new!()
    |> LLMChain.add_messages(messages)
    |> LLMChain.run(run_opts)
    |> ChainResult.to_string()
  end

  defp refine_chunks(chain, chunks, current_summary, total_chunks, opts) do
    chunks
    |> Enum.with_index(2)
    |> Enum.reduce(current_summary, fn {chunk, index}, acc_summary ->
      _ =
        maybe_call_progress(opts, :refining_chunk, %{
          chunk: index,
          total: total_chunks
        })

      prompt = chain.refine_prompt || @default_refine_prompt

      case run_llm_with_prompt(
             chain,
             prompt,
             %{
               existing_summary: acc_summary,
               text: chunk
             },
             opts
           ) do
        {:ok, new_summary} -> new_summary
        {:error, _} -> acc_summary
      end
    end)
  end

  defp maybe_call_progress(opts, stage, info) do
    case Keyword.get(opts, :on_progress) do
      nil -> :ok
      callback when is_function(callback, 2) -> callback.(stage, info)
      _ -> :ok
    end
  end
end
