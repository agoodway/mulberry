defmodule Mulberry.Research.Hybrid do
  @moduledoc """
  Hybrid research implementation combining web and local sources.

  This module implements the Research.Behaviour by combining both
  web-based and local document research strategies for comprehensive
  research coverage.
  """

  @behaviour Mulberry.Research.Behaviour

  require Logger

  alias Mulberry.Research.{Chain, Result, Web, Local}

  @doc """
  Conducts hybrid research using both web and local sources.
  """
  @impl true
  @spec research(String.t(), Chain.t(), Keyword.t()) :: {:ok, Result.t()} | {:error, term()}
  def research(topic, %Chain{} = chain, opts \\ []) do
    opts = Keyword.put(opts, :topic, topic)
    
    # Split source allocation between web and local
    _web_chain = %{chain | max_sources: div(chain.max_sources, 2) + rem(chain.max_sources, 2)}
    _local_chain = %{chain | max_sources: div(chain.max_sources, 2)}
    
    with {:ok, sources} <- gather_sources(topic, chain, opts),
         _ <- maybe_call_progress(opts, :sources_gathered, %{count: length(sources)}),
         {:ok, analysis} <- analyze_sources(sources, chain, opts),
         _ <- maybe_call_progress(opts, :analysis_complete, %{sources_analyzed: length(sources)}) do
      synthesize_findings(analysis, chain, opts)
    end
  end

  @doc """
  Gathers sources from both web and local documents.
  """
  @impl true
  @spec gather_sources(String.t(), Chain.t(), Keyword.t()) :: {:ok, [Document.t()]} | {:error, term()}
  def gather_sources(topic, %Chain{} = chain, opts \\ []) do
    # Run web and local gathering in parallel
    web_task = Task.async(fn ->
      web_chain = %{chain | max_sources: div(chain.max_sources, 2) + rem(chain.max_sources, 2)}
      Web.gather_sources(topic, web_chain, opts)
    end)
    
    local_task = Task.async(fn ->
      local_chain = %{chain | max_sources: div(chain.max_sources, 2)}
      Local.gather_sources(topic, local_chain, opts)
    end)
    
    # Collect results
    web_result = Task.await(web_task, :infinity)
    local_result = Task.await(local_task, :infinity)
    
    case {web_result, local_result} do
      {{:ok, web_sources}, {:ok, local_sources}} ->
        combined_sources = web_sources ++ local_sources
        _ = maybe_log(chain, "Gathered #{length(web_sources)} web sources and #{length(local_sources)} local sources")
        {:ok, combined_sources}
      
      {{:ok, web_sources}, {:error, _}} ->
        _ = maybe_log(chain, "Local search failed, using only web sources")
        {:ok, web_sources}
      
      {{:error, _}, {:ok, local_sources}} ->
        _ = maybe_log(chain, "Web search failed, using only local sources")
        {:ok, local_sources}
      
      {{:error, web_error}, {:error, local_error}} ->
        {:error, {:both_failed, web: web_error, local: local_error}}
    end
  end

  @doc """
  Analyzes sources from both web and local documents.
  """
  @impl true
  @spec analyze_sources([Document.t()], Chain.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
  def analyze_sources(sources, %Chain{} = chain, opts \\ []) do
    # Separate sources by type
    {web_sources, local_sources} = separate_sources(sources)
    
    _ = maybe_call_progress(opts, :analyzing_sources, %{
      web: length(web_sources),
      local: length(local_sources)
    })
    
    # Analyze each type using appropriate strategy
    web_analysis = if Enum.empty?(web_sources) do
      {:ok, %{source_analyses: %{}, source_count: 0, analyzed_count: 0}}
    else
      Web.analyze_sources(web_sources, chain, opts)
    end
    
    local_analysis = if Enum.empty?(local_sources) do
      {:ok, %{source_analyses: %{}, source_count: 0, analyzed_count: 0}}
    else
      Local.analyze_sources(local_sources, chain, opts)
    end
    
    case {web_analysis, local_analysis} do
      {{:ok, web_data}, {:ok, local_data}} ->
        combined_analyses = Map.merge(
          web_data.source_analyses,
          local_data.source_analyses
        )
        
        {:ok, %{
          source_analyses: combined_analyses,
          source_count: web_data.source_count + local_data.source_count,
          analyzed_count: web_data.analyzed_count + local_data.analyzed_count,
          web_count: web_data.analyzed_count,
          local_count: local_data.analyzed_count
        }}
      
      {{:ok, web_data}, _} -> {:ok, web_data}
      {_, {:ok, local_data}} -> {:ok, local_data}
      {error, _} -> error
    end
  end

  @doc """
  Synthesizes findings from hybrid source analysis.
  """
  @impl true
  @spec synthesize_findings(map(), Chain.t(), Keyword.t()) :: {:ok, Result.t()} | {:error, term()}
  def synthesize_findings(analysis_data, %Chain{} = chain, opts) do
    # Use Web module's synthesis as it's the same process
    case Web.synthesize_findings(analysis_data, chain, opts) do
      {:ok, result} ->
        # Update metadata to reflect hybrid strategy
        updated_metadata = Map.merge(result.metadata, %{
          strategy: :hybrid,
          web_sources: Map.get(analysis_data, :web_count, 0),
          local_sources: Map.get(analysis_data, :local_count, 0)
        })
        
        {:ok, %{result | metadata: updated_metadata}}
      
      error -> error
    end
  end

  # Private functions

  defp separate_sources(sources) do
    Enum.split_with(sources, fn source ->
      case source do
        %Mulberry.Document.WebPage{} -> true
        %{url: _} -> true
        _ -> false
      end
    end)
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