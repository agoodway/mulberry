defmodule Mulberry.Research.Behaviour do
  @moduledoc """
  Defines the behavior for research strategy implementations.

  This module specifies the callbacks that must be implemented by
  different research strategies (web, local, hybrid).
  """

  alias Mulberry.Research.{Chain, Result}
  alias Mulberry.Document

  @doc """
  Conducts research on a topic using the implementation's strategy.

  This is the main entry point for a research strategy.
  """
  @callback research(String.t(), Chain.t(), Keyword.t()) ::
              {:ok, Result.t()} | {:error, term()}

  @doc """
  Gathers relevant source documents for the research topic.

  Returns a list of Document implementations (WebPage, File, etc.)
  that are relevant to the research topic.
  """
  @callback gather_sources(String.t(), Chain.t(), Keyword.t()) ::
              {:ok, [Document.t()]} | {:error, term()}

  @doc """
  Analyzes the gathered sources to extract key information.

  Returns a map containing:
  - `:summaries` - Map of document ID to summary
  - `:key_points` - List of important findings
  - `:themes` - Common themes across sources
  """
  @callback analyze_sources([Document.t()], Chain.t(), Keyword.t()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Synthesizes the analysis into final research findings.

  Takes the analysis results and produces a comprehensive summary
  with citations and confidence scores.
  """
  @callback synthesize_findings(map(), Chain.t(), Keyword.t()) ::
              {:ok, Result.t()} | {:error, term()}
end
