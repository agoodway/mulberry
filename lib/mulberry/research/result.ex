defmodule Mulberry.Research.Result do
  @moduledoc """
  Represents the structured output of a research operation.

  This struct contains all the findings, sources, and metadata
  from a research session.
  """

  alias Mulberry.Document

  defstruct [
    :topic,
    :summary,
    :detailed_content,
    :key_findings,
    :sources,
    :citations,
    :themes,
    :confidence_score,
    :related_topics,
    :metadata,
    :stats
  ]

  @type finding :: %{
          text: String.t(),
          source_ids: [String.t()],
          confidence: float()
        }

  @type citation :: %{
          text: String.t(),
          source_id: String.t(),
          location: String.t() | nil
        }

  @type t :: %__MODULE__{
          topic: String.t(),
          summary: String.t(),
          detailed_content: String.t() | nil,
          key_findings: [finding()],
          sources: [Document.t()],
          citations: [citation()],
          themes: [String.t()],
          confidence_score: float(),
          related_topics: [String.t()],
          metadata: map(),
          stats: map() | nil
        }

  @doc """
  Creates a new Research.Result struct with the given attributes.

  ## Required fields
  - `:topic` - The research topic
  - `:summary` - Executive summary of findings
  - `:sources` - List of source documents

  ## Optional fields
  - `:key_findings` - List of key findings with citations
  - `:citations` - List of specific citations
  - `:themes` - Common themes identified
  - `:confidence_score` - Overall confidence (0.0-1.0)
  - `:related_topics` - Suggested related research topics
  - `:metadata` - Additional metadata (timestamps, strategy used, etc.)
  """
  @spec new(map()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required_fields(attrs),
         :ok <- validate_field_types(attrs) do
      result = struct(__MODULE__, attrs)
      {:ok, result}
    end
  end

  @doc """
  Creates a new Research.Result struct or raises an error.
  """
  @spec new!(map()) :: t() | no_return()
  def new!(attrs) when is_map(attrs) do
    case new(attrs) do
      {:ok, result} -> result
      {:error, message} -> raise ArgumentError, message
    end
  end

  @doc """
  Adds a key finding to the result.
  """
  @spec add_finding(t(), String.t(), [String.t()], float()) :: t()
  def add_finding(%__MODULE__{} = result, text, source_ids, confidence \\ 0.8) do
    finding = %{
      text: text,
      source_ids: source_ids,
      confidence: confidence
    }
    
    %{result | key_findings: (result.key_findings || []) ++ [finding]}
  end

  @doc """
  Adds a citation to the result.
  """
  @spec add_citation(t(), String.t(), String.t(), String.t() | nil) :: t()
  def add_citation(%__MODULE__{} = result, text, source_id, location \\ nil) do
    citation = %{
      text: text,
      source_id: source_id,
      location: location
    }
    
    %{result | citations: (result.citations || []) ++ [citation]}
  end

  @doc """
  Calculates the average confidence score from all findings.
  """
  @spec calculate_confidence(t()) :: t()
  def calculate_confidence(%__MODULE__{key_findings: findings} = result) when is_list(findings) do
    if Enum.empty?(findings) do
      %{result | confidence_score: 0.5}
    else
      avg_confidence =
        findings
        |> Enum.map(& &1.confidence)
        |> Enum.sum()
        |> Kernel./(length(findings))
      
      %{result | confidence_score: avg_confidence}
    end
  end

  def calculate_confidence(%__MODULE__{} = result) do
    %{result | confidence_score: 0.5}
  end

  @doc """
  Converts the result to a formatted string for display.
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{} = result) do
    """
    Research Topic: #{result.topic}
    
    Summary:
    #{result.summary}
    
    Key Findings (#{length(result.key_findings || [])}):
    #{format_findings(result.key_findings)}
    
    Sources (#{length(result.sources || [])}):
    #{format_sources(result.sources)}
    
    Confidence Score: #{format_confidence(result.confidence_score)}
    
    Related Topics: #{Enum.join(result.related_topics || [], ", ")}
    """
  end

  # Private functions

  defp validate_required_fields(attrs) do
    required = [:topic, :summary, :sources]
    missing = required -- Map.keys(attrs)
    
    if Enum.empty?(missing) do
      :ok
    else
      {:error, "Missing required fields: #{Enum.join(missing, ", ")}"}
    end
  end

  defp validate_field_types(attrs) do
    validations = [
      {:topic, &is_binary/1, "must be a string"},
      {:summary, &is_binary/1, "must be a string"},
      {:sources, &is_list/1, "must be a list"},
      {:key_findings, &(is_nil(&1) or is_list(&1)), "must be a list or nil"},
      {:confidence_score, &(is_nil(&1) or is_float(&1) or is_integer(&1)), "must be a number or nil"}
    ]
    
    errors =
      validations
      |> Enum.filter(fn {field, validator, _} ->
        Map.has_key?(attrs, field) and not validator.(Map.get(attrs, field))
      end)
      |> Enum.map(fn {field, _, message} -> "#{field} #{message}" end)
    
    if Enum.empty?(errors) do
      :ok
    else
      {:error, "Validation errors: #{Enum.join(errors, ", ")}"}
    end
  end

  defp format_findings(nil), do: "None"
  defp format_findings([]), do: "None"
  
  defp format_findings(findings) do
    findings
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {finding, index} ->
      "#{index}. #{finding.text} (confidence: #{format_confidence(finding.confidence)})"
    end)
  end

  defp format_sources(nil), do: "None"
  defp format_sources([]), do: "None"
  
  defp format_sources(sources) do
    sources
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {source, index} ->
      # Try to get a title or URL from the source
      title = get_source_title(source)
      "#{index}. #{title}"
    end)
  end

  defp get_source_title(%{title: title}) when is_binary(title), do: title
  defp get_source_title(%{url: url}) when is_binary(url), do: url
  defp get_source_title(%{path: path}) when is_binary(path), do: Path.basename(path)
  defp get_source_title(_), do: "Unknown source"

  defp format_confidence(nil), do: "N/A"
  defp format_confidence(score) when is_float(score), do: "#{round(score * 100)}%"
  defp format_confidence(score) when is_integer(score), do: "#{score}%"
end