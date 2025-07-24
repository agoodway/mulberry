defmodule Mulberry do
  @moduledoc false

  alias Mulberry.Document
  alias Mulberry.Document.WebPage
  alias Mulberry.Document.File
  alias Mulberry.Research
  alias Flamel.Chain

  @doc """
  Retrieves configuration values for the Mulberry application.
  
  First checks application environment, then falls back to system environment variables.
  
  ## Environment Variable Mapping
  
  - `:brave_api_key` → `BRAVE_API_KEY`
  - `:scraping_bee_api_key` → `SCRAPING_BEE_API_KEY`
  - `:openai_api_key` → `OPENAI_API_KEY`
  - `:anthropic_api_key` → `ANTHROPIC_API_KEY`
  - `:google_api_key` → `GOOGLE_API_KEY`
  - `:mistral_api_key` → `MISTRAL_API_KEY`
  - `:llm_provider` → `MULBERRY_LLM_PROVIDER`
  
  For other keys, converts to uppercase and prepends `MULBERRY_` if not already present.
  
  ## Examples
  
      # With app config set
      Application.put_env(:mulberry, :brave_api_key, "app_key")
      Mulberry.config(:brave_api_key) #=> "app_key"
      
      # With only env var set
      System.put_env("BRAVE_API_KEY", "env_key")
      Mulberry.config(:brave_api_key) #=> "env_key"
  """
  @spec config(atom()) :: any()
  def config(key) do
    case Application.get_env(:mulberry, key) do
      nil -> get_env_var(key)
      value -> value
    end
  end
  
  defp get_env_var(key) do
    env_key = map_to_env_var(key)
    System.get_env(env_key)
  end
  
  defp map_to_env_var(key) do
    known_mappings = %{
      brave_api_key: "BRAVE_API_KEY",
      scraping_bee_api_key: "SCRAPING_BEE_API_KEY",
      openai_api_key: "OPENAI_API_KEY",
      anthropic_api_key: "ANTHROPIC_API_KEY",
      google_api_key: "GOOGLE_API_KEY",
      mistral_api_key: "MISTRAL_API_KEY",
      llm_provider: "MULBERRY_LLM_PROVIDER"
    }
    
    case Map.get(known_mappings, key) do
      nil -> build_env_key(key)
      env_key -> env_key
    end
  end
  
  defp build_env_key(key) do
    key_str = key |> Atom.to_string() |> String.upcase()
    if String.starts_with?(key_str, "MULBERRY_") do
      key_str
    else
      "MULBERRY_#{key_str}"
    end
  end

  @doc """
  Searches using the specified module and returns documents matching the query.
  """
  @spec search(module(), String.t(), pos_integer()) :: [any()]
  def search(module, query, limit \\ 3) do
    query
    |> module.search(limit)
    |> module.to_documents()
  end

  @doc """
  Generates a summary for the given URI (either a URL or file path).
  """
  @spec summarize(String.t(), Keyword.t()) :: String.t() | {:error, any()}
  def summarize(uri, opts \\ []) do
    if String.starts_with?(uri, "http") do
      WebPage.new(%{url: uri})
    else
      File.new(%{path: uri})
    end
    |> Chain.new()
    |> Chain.apply(&Document.load(&1, opts))
    |> Chain.apply(&Document.generate_summary/1)
    |> Chain.to_value()
    |> Document.to_text()
  end

  @doc """
  Conducts comprehensive research on a topic using various strategies.
  
  ## Examples
  
      # Simple web research
      {:ok, result} = Mulberry.research("quantum computing applications")
      
      # Research with options
      {:ok, result} = Mulberry.research("machine learning trends",
        strategy: :hybrid,
        max_sources: 10,
        depth: 2
      )
  
  See `Mulberry.Research` for more options and details.
  """
  @spec research(String.t(), Keyword.t()) :: {:ok, Research.Result.t()} | {:error, term()}
  defdelegate research(topic, opts \\ []), to: Research
end
