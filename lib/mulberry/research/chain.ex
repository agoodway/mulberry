defmodule Mulberry.Research.Chain do
  @moduledoc """
  Configuration schema for research operations using Ecto.

  This module defines the configuration options for research chains,
  including LLM settings, search parameters, and analysis prompts.
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias LangChain.Utils
  alias __MODULE__

  @primary_key false
  embedded_schema do
    field(:llm, :any, virtual: true)
    field(:strategy, Ecto.Enum, values: [:web, :local, :hybrid], default: :web)
    field(:max_sources, :integer, default: 5)
    field(:search_depth, :integer, default: 1)
    field(:chunk_size, :integer, default: 1000)
    field(:chunk_overlap, :integer, default: 100)
    field(:verbose, :boolean, default: false)
    
    # Custom prompts
    field(:search_query_prompt, :string)
    field(:source_analysis_prompt, :string)
    field(:synthesis_prompt, :string)
    field(:finding_extraction_prompt, :string)
    
    # Content generation settings
    field(:content_length, :string, default: "medium")
    
    # Search and retrieval options
    field(:search_options, :map, default: %{})
    field(:retriever_options, :map, default: %{})
    
    # Search modules configuration
    field(:search_modules, {:array, :map}, default: [])
    # Virtual field for backward compatibility
    field(:search_module, :any, virtual: true)
    field(:search_module_options, :map, virtual: true)
    
    # Filtering and ranking
    field(:min_source_relevance, :float, default: 0.7)
    field(:include_domains, {:array, :string}, default: [])
    field(:exclude_domains, {:array, :string}, default: [])
  end

  @type t :: %Chain{
          llm: term(),
          strategy: atom(),
          max_sources: pos_integer(),
          search_depth: pos_integer(),
          chunk_size: pos_integer(),
          chunk_overlap: non_neg_integer(),
          verbose: boolean(),
          search_query_prompt: String.t() | nil,
          source_analysis_prompt: String.t() | nil,
          synthesis_prompt: String.t() | nil,
          finding_extraction_prompt: String.t() | nil,
          content_length: String.t(),
          search_options: map(),
          retriever_options: map(),
          search_modules: [map()],
          search_module: term() | nil,
          search_module_options: map(),
          min_source_relevance: float(),
          include_domains: [String.t()],
          exclude_domains: [String.t()]
        }

  @create_fields [
    :llm,
    :strategy,
    :max_sources,
    :search_depth,
    :chunk_size,
    :chunk_overlap,
    :verbose,
    :search_query_prompt,
    :source_analysis_prompt,
    :synthesis_prompt,
    :finding_extraction_prompt,
    :content_length,
    :search_options,
    :retriever_options,
    :search_modules,
    :search_module,
    :search_module_options,
    :min_source_relevance,
    :include_domains,
    :exclude_domains
  ]

  @required_fields []

  # Default prompts
  @default_search_query_prompt """
  You are a research assistant helping to formulate effective search queries.
  Given the research topic, generate 3-5 search queries that would help gather comprehensive information.
  
  Research topic: <%= @topic %>
  
  Consider different angles and aspects of the topic. Return only the search queries, one per line.
  """

  @default_source_analysis_prompt """
  You are analyzing a source document for research purposes.
  Extract the most important and relevant information related to the research topic.
  
  Research topic: <%= @topic %>
  
  Source content:
  <%= @content %>
  
  Provide a structured analysis including:
  1. Key relevant information
  2. Important facts and figures
  3. Notable quotes or statements
  4. Credibility indicators
  5. Gaps or limitations in the information
  """

  @default_synthesis_prompt """
  You are synthesizing research findings from multiple sources.
  Create a comprehensive summary that integrates information from all sources.
  
  Research topic: <%= @topic %>
  
  Source analyses:
  <%= @analyses %>
  
  Provide:
  1. An executive summary (2-3 paragraphs)
  2. Key findings across all sources
  3. Common themes and patterns
  4. Contradictions or disagreements between sources
  5. Confidence assessment of the findings
  6. Suggested areas for further research
  """

  @default_finding_extraction_prompt """
  You are extracting specific findings from research analysis.
  Identify discrete, citable findings that directly address the research topic.
  
  Research topic: <%= @topic %>
  
  Analysis:
  <%= @analysis %>
  
  For each finding, provide:
  - The finding statement (clear and concise)
  - Supporting evidence or data
  - Source attribution
  - Confidence level (0.0-1.0)
  
  Format as a list of findings.
  """

  @doc """
  Creates a new ResearchChain with the given configuration.

  ## Options

  - `:llm` - The LLM instance to use for analysis (uses default if not provided)
  - `:strategy` - Research strategy (:web, :local, :hybrid). Default: :web
  - `:max_sources` - Maximum number of sources to analyze (1-100). Default: 5
  - `:search_depth` - Depth of research (1-3). Default: 1
  - `:chunk_size` - Size of text chunks for processing. Default: 1000
  - `:chunk_overlap` - Overlap between chunks. Default: 100
  - `:verbose` - Enable verbose logging. Default: false
  - `:search_query_prompt` - Custom prompt for query generation
  - `:source_analysis_prompt` - Custom prompt for source analysis
  - `:synthesis_prompt` - Custom prompt for synthesis
  - `:finding_extraction_prompt` - Custom prompt for finding extraction
  - `:search_options` - Options to pass to search providers
  - `:retriever_options` - Options to pass to content retrievers
  - `:min_source_relevance` - Minimum relevance score for sources. Default: 0.7
  - `:include_domains` - List of domains to prioritize
  - `:exclude_domains` - List of domains to exclude
  """
  @spec new(attrs :: map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def new(attrs \\ %{}) do
    attrs = ensure_llm(attrs)
    
    %Chain{}
    |> cast(attrs, @create_fields)
    |> validate_required(@required_fields)
    |> validate_number(:max_sources, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_number(:search_depth, greater_than: 0, less_than_or_equal_to: 3)
    |> validate_number(:chunk_size, greater_than: 0)
    |> validate_number(:chunk_overlap, greater_than_or_equal_to: 0)
    |> validate_number(:min_source_relevance, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> Utils.validate_llm_is_struct()
    |> apply_action(:insert)
  end

  @doc """
  Creates a new ResearchChain and returns it or raises an error if invalid.
  """
  @spec new!(attrs :: map()) :: t() | no_return()
  def new!(attrs \\ %{}) do
    case new(attrs) do
      {:ok, chain} -> chain
      {:error, changeset} -> raise ArgumentError, format_errors(changeset)
    end
  end

  @doc """
  Returns the search query prompt, using default if not customized.
  """
  @spec get_search_query_prompt(t()) :: String.t()
  def get_search_query_prompt(%Chain{search_query_prompt: nil}), do: @default_search_query_prompt
  def get_search_query_prompt(%Chain{search_query_prompt: prompt}), do: prompt

  @doc """
  Returns the source analysis prompt, using default if not customized.
  """
  @spec get_source_analysis_prompt(t()) :: String.t()
  def get_source_analysis_prompt(%Chain{source_analysis_prompt: nil}), do: @default_source_analysis_prompt
  def get_source_analysis_prompt(%Chain{source_analysis_prompt: prompt}), do: prompt

  @doc """
  Returns the synthesis prompt, using default if not customized.
  """
  @spec get_synthesis_prompt(t()) :: String.t()
  def get_synthesis_prompt(%Chain{synthesis_prompt: nil}), do: @default_synthesis_prompt
  def get_synthesis_prompt(%Chain{synthesis_prompt: prompt}), do: prompt

  @doc """
  Returns the finding extraction prompt, using default if not customized.
  """
  @spec get_finding_extraction_prompt(t()) :: String.t()
  def get_finding_extraction_prompt(%Chain{finding_extraction_prompt: nil}), do: @default_finding_extraction_prompt
  def get_finding_extraction_prompt(%Chain{finding_extraction_prompt: prompt}), do: prompt

  @doc """
  Gets the normalized search modules configuration from the chain.
  
  Handles backward compatibility by converting single search_module to modules list.
  """
  @spec get_search_modules(t()) :: [%{module: module(), options: map(), weight: float()}]
  def get_search_modules(%Chain{} = chain) do
    cond do
      # If search_modules is populated, use it
      chain.search_modules != [] ->
        normalize_search_modules(chain.search_modules)
      
      # Backward compatibility: if search_module is set
      chain.search_module != nil ->
        [%{
          module: chain.search_module,
          options: chain.search_module_options || %{},
          weight: 1.0
        }]
      
      # Default to Brave search
      true ->
        [%{
          module: Mulberry.Search.Brave,
          options: %{},
          weight: 1.0
        }]
    end
  end

  # Private functions

  defp ensure_llm(attrs) do
    if Map.has_key?(attrs, :llm) do
      attrs
    else
      # Use the default LLM from config
      case Mulberry.LangChain.Config.get_llm() do
        {:ok, llm} -> Map.put(attrs, :llm, llm)
        _ -> attrs
      end
    end
  end

  defp format_errors(changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)
    
    Enum.map_join(errors, "; ", fn {field, messages} -> "#{field}: #{Enum.join(messages, ", ")}" end)
  end

  defp normalize_search_modules(modules) do
    Enum.map(modules, fn module_config ->
      %{
        module: Map.get(module_config, :module) || Map.get(module_config, "module"),
        options: Map.get(module_config, :options) || Map.get(module_config, "options") || %{},
        weight: Map.get(module_config, :weight) || Map.get(module_config, "weight") || 1.0
      }
    end)
  end
end