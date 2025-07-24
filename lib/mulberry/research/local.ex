defmodule Mulberry.Research.Local do
  @moduledoc """
  Local document research implementation.

  This module implements the Research.Behaviour for conducting research
  using local files and documents. It searches through local documents
  to find relevant information for the research topic.
  """

  @behaviour Mulberry.Research.Behaviour

  require Logger

  alias Mulberry.Research.{Chain, Result}
  alias Mulberry.{Document, Text}
  alias LangChain.Chains.LLMChain
  alias LangChain.PromptTemplate
  alias LangChain.Utils.ChainResult

  @doc """
  Conducts local document-based research on a topic.
  """
  @impl true
  @spec research(String.t(), Chain.t(), Keyword.t()) :: {:ok, Result.t()} | {:error, term()}
  def research(topic, %Chain{} = chain, opts \\ []) do
    opts = Keyword.put(opts, :topic, topic)
    
    with {:ok, sources} <- gather_sources(topic, chain, opts),
         _ <- maybe_call_progress(opts, :sources_gathered, %{count: length(sources)}),
         {:ok, analysis} <- analyze_sources(sources, chain, opts),
         _ <- maybe_call_progress(opts, :analysis_complete, %{sources_analyzed: length(sources)}) do
      synthesize_findings(analysis, chain, opts)
    end
  end

  @doc """
  Gathers local document sources for the research topic.
  """
  @impl true
  @spec gather_sources(String.t(), Chain.t(), Keyword.t()) :: {:ok, [Document.t()]} | {:error, term()}
  def gather_sources(topic, %Chain{} = chain, opts \\ []) do
    search_paths = Keyword.get(opts, :search_paths, ["."])
    file_patterns = Keyword.get(opts, :file_patterns, ["*.txt", "*.md", "*.pdf"])
    
    with {:ok, file_paths} <- find_files(search_paths, file_patterns),
         _ <- maybe_log(chain, "Found #{length(file_paths)} files to search"),
         {:ok, relevant_files} <- find_relevant_files(file_paths, topic, chain, opts),
         {:ok, documents} <- load_documents(relevant_files, chain) do
      
      selected_docs = Enum.take(documents, chain.max_sources)
      
      _ = maybe_call_progress(opts, :documents_selected, %{
        total_found: length(documents),
        selected: length(selected_docs)
      })
      
      {:ok, selected_docs}
    end
  end

  @doc """
  Analyzes gathered local document sources.
  """
  @impl true
  @spec analyze_sources([Document.t()], Chain.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
  def analyze_sources(sources, %Chain{} = chain, opts \\ []) do
    topic = Keyword.get(opts, :topic, "research")
    
    analyses =
      sources
      |> Enum.with_index()
      |> Enum.map(fn {source, index} ->
        _ = maybe_call_progress(opts, :analyzing_source, %{
          current: index + 1,
          total: length(sources),
          file: get_source_path(source)
        })
        
        case analyze_single_source(source, topic, chain) do
          {:ok, analysis} -> {source, analysis}
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()
    
    {:ok, %{
      source_analyses: analyses,
      source_count: length(sources),
      analyzed_count: map_size(analyses)
    }}
  end

  @doc """
  Synthesizes findings from local document analysis.
  """
  @impl true
  @spec synthesize_findings(map(), Chain.t(), Keyword.t()) :: {:ok, Result.t()} | {:error, term()}
  def synthesize_findings(%{source_analyses: analyses} = analysis_data, %Chain{} = chain, opts) do
    topic = Keyword.get(opts, :topic, "research")
    
    with {:ok, synthesis} <- generate_synthesis(analyses, topic, chain),
         {:ok, findings} <- extract_findings(synthesis, topic, chain),
         sources <- Map.keys(analyses) do
      
      result = %{
        topic: topic,
        summary: synthesis.summary,
        sources: sources,
        key_findings: findings,
        themes: synthesis.themes,
        related_topics: synthesis.related_topics,
        metadata: %{
          strategy: :local,
          sources_analyzed: analysis_data.analyzed_count,
          timestamp: DateTime.utc_now()
        }
      }
      
      result
      |> Result.new!()
      |> Result.calculate_confidence()
      |> then(&{:ok, &1})
    end
  end

  # Private functions

  defp find_files(search_paths, patterns) do
    files =
      search_paths
      |> Enum.flat_map(fn path ->
        patterns
        |> Enum.flat_map(fn pattern ->
          Path.wildcard(Path.join([path, "**", pattern]))
        end)
      end)
      |> Enum.uniq()
      |> Enum.filter(&Elixir.File.regular?/1)
    
    {:ok, files}
  end

  defp find_relevant_files(file_paths, topic, %Chain{} = chain, _opts) do
    # Score files based on filename relevance and content sampling
    scored_files =
      file_paths
      |> Enum.map(fn path ->
        score = calculate_file_relevance(path, topic, chain)
        {path, score}
      end)
      |> Enum.filter(fn {_, score} -> score >= chain.min_source_relevance end)
      |> Enum.sort_by(fn {_, score} -> score end, :desc)
      |> Enum.map(fn {path, _} -> path end)
    
    {:ok, scored_files}
  end

  defp calculate_file_relevance(path, topic, _chain) do
    # Simple relevance scoring based on filename
    # Could be enhanced with content sampling
    filename = Path.basename(path) |> String.downcase()
    topic_words = String.split(topic, ~r/\s+/) |> Enum.map(&String.downcase/1)
    
    matches = Enum.count(topic_words, &String.contains?(filename, &1))
    
    # Normalize score between 0 and 1
    min(matches / length(topic_words), 1.0)
  end

  defp load_documents(file_paths, %Chain{} = _chain) do
    documents =
      file_paths
      |> Enum.map(fn path ->
        case Mulberry.Document.File.new(path) do
          {:ok, doc} -> doc
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
    
    {:ok, documents}
  end

  defp analyze_single_source(source, topic, %Chain{} = chain) do
    with {:ok, text} <- Document.to_text(source) do
      # Chunk if needed
      chunks = Text.split(text)
      analysis_text = Enum.join(Enum.take(chunks, 10), "\n\n")
      
      prompt = Chain.get_source_analysis_prompt(chain)
      
      messages =
        [
          PromptTemplate.new!(%{
            role: :user,
            text: prompt
          })
        ]
        |> PromptTemplate.to_messages!(%{
          topic: topic,
          content: analysis_text
        })
      
      run_llm(chain, messages)
    end
  end

  defp generate_synthesis(analyses, topic, %Chain{} = chain) do
    # Format analyses for synthesis
    analyses_text =
      analyses
      |> Enum.map_join("\n\n---\n\n", fn {source, analysis} ->
        path = get_source_path(source)
        "Source: #{path}\n#{analysis}"
      end)
    
    prompt = Chain.get_synthesis_prompt(chain)
    
    messages =
      [
        PromptTemplate.new!(%{
          role: :user,
          text: prompt
        })
      ]
      |> PromptTemplate.to_messages!(%{
        topic: topic,
        analyses: analyses_text
      })
    
    case run_llm(chain, messages) do
      {:ok, response} ->
        {:ok, parse_synthesis_response(response)}
      
      error -> error
    end
  end

  defp extract_findings(synthesis, topic, %Chain{} = chain) do
    prompt = Chain.get_finding_extraction_prompt(chain)
    
    messages =
      [
        PromptTemplate.new!(%{
          role: :user,
          text: prompt
        })
      ]
      |> PromptTemplate.to_messages!(%{
        topic: topic,
        analysis: synthesis.summary
      })
    
    case run_llm(chain, messages) do
      {:ok, response} ->
        findings = parse_findings_response(response)
        {:ok, findings}
      
      error -> error
    end
  end

  defp parse_synthesis_response(response) do
    # Reuse the parsing logic from Web module
    sections = String.split(response, ~r/\n{2,}/)
    
    %{
      summary: Enum.at(sections, 0, response),
      themes: extract_list_section(response, "themes"),
      related_topics: extract_list_section(response, "related|further research")
    }
  end

  defp parse_findings_response(response) do
    response
    |> String.split(~r/\n[-*•]|\d+\./)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn finding_text ->
      %{
        text: clean_finding_text(finding_text),
        source_ids: [],
        confidence: 0.8
      }
    end)
  end

  defp extract_list_section(text, pattern) do
    regex = ~r/#{pattern}[:\s]*\n((?:[-*•].+\n?)+)/i
    
    case Regex.run(regex, text) do
      [_, section] ->
        section
        |> String.split(~r/\n[-*•]/)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
      
      _ -> []
    end
  end

  defp clean_finding_text(text) do
    text
    |> String.replace(~r/^[-*•]\s*/, "")
    |> String.replace(~r/\(confidence:.*\)$/i, "")
    |> String.trim()
  end

  defp get_source_path(%Mulberry.Document.File{path: path}), do: path
  defp get_source_path(%{path: path}) when is_binary(path), do: path
  defp get_source_path(_), do: "Unknown file"

  defp run_llm(%Chain{llm: llm, verbose: verbose}, messages) do
    %{llm: llm, verbose: verbose}
    |> LLMChain.new!()
    |> LLMChain.add_messages(messages)
    |> LLMChain.run()
    |> ChainResult.to_string()
  end

  defp maybe_log(%Chain{verbose: true}, message), do: Logger.info(message)
  defp maybe_log(_, _), do: :ok

  defp maybe_call_progress(opts, stage, info) do
    case Keyword.get(opts, :on_progress) do
      nil -> :ok
      callback when is_function(callback, 2) -> callback.(stage, info)
      _ -> :ok
    end
  end
end