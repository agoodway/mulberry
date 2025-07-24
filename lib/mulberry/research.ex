defmodule Mulberry.Research do
  @moduledoc """
  High-level research API for conducting comprehensive research on topics.

  This module provides functionality to research topics using various strategies,
  including web searches, local document analysis, and hybrid approaches.
  
  ## Features

  - Multiple research strategies (web, local, hybrid)
  - Configurable search depth and breadth
  - AI-powered analysis and synthesis
  - Progress tracking
  - Structured results with citations

  ## Examples

      # Simple web research
      {:ok, result} = Mulberry.research("machine learning trends 2024")

      # Research with options
      {:ok, result} = Mulberry.research("quantum computing",
        strategy: :web,
        max_sources: 10,
        depth: 2,
        on_progress: fn stage, info ->
          IO.puts("Research \#{stage}: \#{inspect(info)}")
        end
      )

      # Using a custom research chain
      {:ok, chain} = Research.Chain.new(%{
        llm: custom_llm,
        strategy: :hybrid,
        search_depth: 3
      })
      {:ok, result} = Research.run(chain, "renewable energy")
  """

  alias Mulberry.Research.{Chain, Result, Web, Local, Hybrid}

  @default_strategy :web
  @default_max_sources 5
  @default_depth 1

  @doc """
  Conducts research on a given topic using the specified strategy.

  ## Options

  - `:strategy` - Research strategy to use (:web, :local, :hybrid). Default: :web
  - `:max_sources` - Maximum number of sources to analyze. Default: 5
  - `:depth` - Research depth (1-3). Higher values mean more thorough research. Default: 1
  - `:content_length` - Detail level for generated content (:short, :medium, :long, :comprehensive). Default: :medium
  - `:on_progress` - Progress callback function with signature `(stage, info) -> any()`
  - `:llm` - Custom LLM instance to use for analysis
  - `:search_options` - Options to pass to the search provider
  - `:retriever_options` - Options to pass to content retrievers

  ## Returns

  - `{:ok, Research.Result.t()}` - Successful research with structured results
  - `{:error, term()}` - Error if research fails
  """
  @spec research(String.t(), Keyword.t()) :: {:ok, Result.t()} | {:error, term()}
  def research(topic, opts \\ []) when is_binary(topic) do
    strategy = Keyword.get(opts, :strategy, @default_strategy)
    
    with {:ok, chain} <- build_chain(strategy, opts) do
      run(chain, topic, opts)
    end
  end

  @doc """
  Runs a research chain on a given topic.

  This is a lower-level API that allows using a pre-configured Research.Chain.
  """
  @spec run(Chain.t(), String.t(), Keyword.t()) :: {:ok, Result.t()} | {:error, term()}
  def run(%Chain{} = chain, topic, opts \\ []) when is_binary(topic) do
    implementation = get_implementation(chain.strategy)
    implementation.research(topic, chain, opts)
  end

  @doc """
  Lists all available research strategies.
  """
  @spec available_strategies() :: [atom()]
  def available_strategies do
    [:web, :local, :hybrid]
  end

  # Private functions

  defp build_chain(strategy, opts) do
    max_sources = Keyword.get(opts, :max_sources, @default_max_sources)
    depth = Keyword.get(opts, :depth, @default_depth)
    llm = Keyword.get(opts, :llm)
    search_options = Keyword.get(opts, :search_options, %{})
    retriever_options = Keyword.get(opts, :retriever_options, %{})
    content_length = Keyword.get(opts, :content_length, "medium")
    
    chain_attrs = %{
      strategy: strategy,
      max_sources: max_sources,
      search_depth: depth,
      search_options: search_options,
      retriever_options: retriever_options,
      content_length: content_length
    }
    
    chain_attrs = if llm, do: Map.put(chain_attrs, :llm, llm), else: chain_attrs
    
    Chain.new(chain_attrs)
  end

  defp get_implementation(:web), do: Web
  defp get_implementation(:local), do: Local
  defp get_implementation(:hybrid), do: Hybrid
  defp get_implementation(_), do: Web
end