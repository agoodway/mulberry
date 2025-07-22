defmodule Mulberry.LangChain.Config do
  @moduledoc """
  Centralized configuration management for LangChain integration.
  
  Provides a flexible configuration system with built-in defaults,
  environment variable support, and runtime overrides.
  
  ## Configuration Hierarchy
  
  1. Function-level options (highest priority)
  2. Environment variables
  3. Application environment
  4. Built-in defaults (lowest priority)
  
  ## Supported Providers
  
  - `:openai` - OpenAI's GPT models
  - `:anthropic` - Anthropic's Claude models
  - `:google` - Google's Gemini models
  - `:mistral` - Mistral AI models
  - `:ollama` - Local Ollama models
  - `:vertex_ai` - Google Vertex AI
  - `:bumblebee` - Local Bumblebee models
  
  ## Environment Variables
  
  - `MULBERRY_LLM_PROVIDER` - Default LLM provider
  - `MULBERRY_OPENAI_API_KEY` - OpenAI API key
  - `MULBERRY_OPENAI_MODEL` - Default OpenAI model
  - `MULBERRY_ANTHROPIC_API_KEY` - Anthropic API key
  - `MULBERRY_ANTHROPIC_MODEL` - Default Anthropic model
  - Similar patterns for other providers
  """
  
  alias LangChain.ChatModels.{
    ChatOpenAI,
    ChatAnthropic,
    ChatGoogleAI,
    ChatOllamaAI,
    ChatVertexAI,
    ChatBumblebee
  }
  
  @type provider :: :openai | :anthropic | :google | :mistral | :ollama | :vertex_ai | :bumblebee
  @type operation :: :default | :summarize | :title | atom()
  
  @doc """
  Gets an LLM instance configured for the specified operation.
  
  ## Options
  
  - `:provider` - Override the default provider
  - `:model` - Override the default model
  - `:temperature` - Override the temperature setting
  - `:max_tokens` - Override the max tokens setting
  - `:api_key` - Override the API key
  - Any other provider-specific options
  
  ## Examples
  
      # Use defaults
      {:ok, llm} = Config.get_llm()
      
      # Use specific provider
      {:ok, llm} = Config.get_llm(:summarize, provider: :anthropic)
      
      # Override settings
      {:ok, llm} = Config.get_llm(:title, temperature: 0.2, max_tokens: 50)
  """
  @spec get_llm(operation(), Keyword.t()) :: {:ok, struct()} | {:error, term()}
  def get_llm(operation \\ :default, opts \\ []) do
    provider = get_provider(opts)
    
    case get_provider_config(provider, operation, opts) do
      {:ok, config} -> create_llm(provider, config)
      error -> error
    end
  end
  
  @doc """
  Gets the provider to use based on options and configuration.
  """
  @spec get_provider(Keyword.t()) :: provider()
  def get_provider(opts) do
    cond do
      # 1. Check function options
      provider = opts[:provider] -> provider
      
      # 2. Check environment variable
      provider = System.get_env("MULBERRY_LLM_PROVIDER") -> String.to_atom(provider)
      
      # 3. Check application config
      provider = Mulberry.config(:llm_provider) -> provider
      
      # 4. Auto-detect based on available API keys
      System.get_env("MULBERRY_OPENAI_API_KEY") || System.get_env("OPENAI_API_KEY") -> :openai
      System.get_env("MULBERRY_ANTHROPIC_API_KEY") || System.get_env("ANTHROPIC_API_KEY") -> :anthropic
      
      # 5. Default
      true -> :openai
    end
  end
  
  @doc """
  Gets provider-specific configuration with defaults and overrides.
  """
  @spec get_provider_config(provider(), operation(), Keyword.t()) :: {:ok, map()} | {:error, String.t()}
  def get_provider_config(provider, operation, overrides \\ []) do
    with {:ok, base_config} <- default_config(provider),
         {:ok, operation_config} <- operation_defaults(operation),
         {:ok, env_config} <- env_config(provider),
         {:ok, app_config} <- app_config(provider) do
      
      config = 
        base_config
        |> Map.merge(operation_config)
        |> Map.merge(env_config)
        |> Map.merge(app_config)
        |> Map.merge(Map.new(overrides))
      
      validate_config(provider, config)
    end
  end
  
  @doc """
  Default configuration for each provider.
  """
  @spec default_config(provider()) :: {:ok, map()} | {:error, String.t()}
  def default_config(:openai) do
    {:ok, %{
      model: "gpt-3.5-turbo",
      temperature: 0.7,
      frequency_penalty: 0.0,
      stream: false,
      n: 1,
      endpoint: "https://api.openai.com/v1/chat/completions"
    }}
  end
  
  def default_config(:anthropic) do
    {:ok, %{
      model: "claude-3-sonnet-20240229",
      temperature: 0.7,
      stream: false,
      max_tokens: 4096,
      endpoint: "https://api.anthropic.com/v1/messages"
    }}
  end
  
  def default_config(:google) do
    {:ok, %{
      model: "gemini-pro",
      temperature: 0.7,
      stream: false
    }}
  end
  
  def default_config(:mistral) do
    {:ok, %{
      model: "mistral-medium",
      temperature: 0.7,
      stream: false,
      endpoint: "https://api.mistral.ai/v1/chat/completions"
    }}
  end
  
  def default_config(:ollama) do
    {:ok, %{
      model: "llama2",
      temperature: 0.7,
      stream: false,
      endpoint: "http://localhost:11434/api/chat"
    }}
  end
  
  def default_config(:vertex_ai) do
    {:ok, %{
      model: "gemini-pro",
      temperature: 0.7,
      stream: false,
      project_id: System.get_env("GCP_PROJECT_ID"),
      location: "us-central1"
    }}
  end
  
  def default_config(:bumblebee) do
    {:ok, %{
      serving_name: :text_generation,
      stream: false
    }}
  end
  
  def default_config(provider) do
    {:error, "Unknown provider: #{provider}"}
  end
  
  @doc """
  Operation-specific default overrides.
  """
  @spec operation_defaults(operation()) :: {:ok, map()}
  def operation_defaults(:summarize) do
    {:ok, %{
      temperature: 0.3,
      max_tokens: 500
    }}
  end
  
  def operation_defaults(:title) do
    {:ok, %{
      temperature: 0.2,
      max_tokens: 50
    }}
  end
  
  def operation_defaults(_) do
    {:ok, %{}}
  end
  
  @doc """
  Loads configuration from environment variables.
  """
  @spec env_config(provider()) :: {:ok, map()}
  def env_config(provider) do
    prefix = "MULBERRY_#{String.upcase(Atom.to_string(provider))}"
    provider_upper = String.upcase(Atom.to_string(provider))
    
    config = %{}
    |> maybe_add_env_value(:api_key, get_api_key_from_env(prefix, provider_upper))
    |> maybe_add_env_value(:model, System.get_env("#{prefix}_MODEL"))
    |> maybe_add_env_value(:temperature, System.get_env("#{prefix}_TEMPERATURE"), &String.to_float/1)
    |> maybe_add_env_value(:max_tokens, System.get_env("#{prefix}_MAX_TOKENS"), &String.to_integer/1)
    |> maybe_add_env_value(:endpoint, System.get_env("#{prefix}_ENDPOINT"))
    
    {:ok, config}
  end
  
  defp get_api_key_from_env(prefix, provider_upper) do
    System.get_env("#{prefix}_API_KEY") || System.get_env("#{provider_upper}_API_KEY")
  end
  
  defp maybe_add_env_value(config, _key, nil), do: config
  defp maybe_add_env_value(config, key, value), do: Map.put(config, key, value)
  defp maybe_add_env_value(config, _key, nil, _transformer), do: config
  defp maybe_add_env_value(config, key, value, transformer), do: Map.put(config, key, transformer.(value))
  
  @doc """
  Loads configuration from application environment.
  """
  @spec app_config(provider()) :: {:ok, map()}
  def app_config(provider) do
    config = 
      :langchain
      |> Mulberry.config()
      |> get_provider_from_app_config(provider)
    
    {:ok, config}
  end
  
  defp get_provider_from_app_config(nil, _provider), do: %{}
  defp get_provider_from_app_config(langchain_config, provider) do
    langchain_config
    |> Keyword.get(:providers, [])
    |> Keyword.get(provider, [])
    |> Map.new()
  end
  
  @doc """
  Creates an LLM instance for the given provider and configuration.
  """
  @spec create_llm(provider(), map()) :: {:ok, struct()} | {:error, term()}
  def create_llm(:openai, config) do
    case ChatOpenAI.new(config) do
      {:ok, llm} -> {:ok, llm}
      {:error, changeset} -> {:error, format_changeset_errors(changeset)}
    end
  end
  
  def create_llm(:anthropic, config) do
    case ChatAnthropic.new(config) do
      {:ok, llm} -> {:ok, llm}
      {:error, changeset} -> {:error, format_changeset_errors(changeset)}
    end
  end
  
  def create_llm(:google, config) do
    case ChatGoogleAI.new(config) do
      {:ok, llm} -> {:ok, llm}
      {:error, changeset} -> {:error, format_changeset_errors(changeset)}
    end
  end
  
  def create_llm(:mistral, _config) do
    {:error, "Mistral AI provider is not available in the current LangChain version"}
  end
  
  def create_llm(:ollama, config) do
    case ChatOllamaAI.new(config) do
      {:ok, llm} -> {:ok, llm}
      {:error, changeset} -> {:error, format_changeset_errors(changeset)}
    end
  end
  
  def create_llm(:vertex_ai, config) do
    case ChatVertexAI.new(config) do
      {:ok, llm} -> {:ok, llm}
      {:error, changeset} -> {:error, format_changeset_errors(changeset)}
    end
  end
  
  def create_llm(:bumblebee, config) do
    case ChatBumblebee.new(config) do
      {:ok, llm} -> {:ok, llm}
      {:error, changeset} -> {:error, format_changeset_errors(changeset)}
    end
  end
  
  def create_llm(provider, _config) do
    {:error, "Unsupported provider: #{provider}"}
  end
  
  @doc """
  Validates provider configuration.
  """
  @spec validate_config(provider(), map()) :: {:ok, map()} | {:error, String.t()}
  def validate_config(provider, config) when provider in [:openai, :anthropic, :google, :mistral] do
    if Map.get(config, :api_key) do
      {:ok, config}
    else
      {:error, "API key required for #{provider}. Set #{String.upcase(Atom.to_string(provider))}_API_KEY or MULBERRY_#{String.upcase(Atom.to_string(provider))}_API_KEY environment variable."}
    end
  end
  
  def validate_config(:vertex_ai, config) do
    if config[:project_id] do
      {:ok, config}
    else
      {:error, "Project ID required for Vertex AI. Set GCP_PROJECT_ID environment variable."}
    end
  end
  
  def validate_config(_provider, config) do
    {:ok, config}
  end
  
  defp format_changeset_errors(changeset) do
    errors = 
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)
    
    Enum.map_join(errors, ", ", fn {field, messages} ->
      "#{field}: #{Enum.join(messages, ", ")}"
    end)
  end
end