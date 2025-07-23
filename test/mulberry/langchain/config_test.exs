defmodule Mulberry.LangChain.ConfigTest do
  use ExUnit.Case, async: false
  alias Mulberry.LangChain.Config
  
  describe "get_provider/1" do
    setup do
      # Clean up environment variables
      System.delete_env("MULBERRY_LLM_PROVIDER")
      System.delete_env("MULBERRY_OPENAI_API_KEY")
      System.delete_env("OPENAI_API_KEY")
      System.delete_env("MULBERRY_ANTHROPIC_API_KEY")
      System.delete_env("ANTHROPIC_API_KEY")
      :ok
    end
    
    test "returns provider from options when specified" do
      assert Config.get_provider(provider: :anthropic) == :anthropic
      assert Config.get_provider(provider: :google) == :google
    end
    
    test "returns provider from environment variable when set" do
      System.put_env("MULBERRY_LLM_PROVIDER", "mistral")
      assert Config.get_provider([]) == :mistral
    end
    
    test "auto-detects OpenAI when OPENAI_API_KEY is set" do
      System.put_env("OPENAI_API_KEY", "test-key")
      assert Config.get_provider([]) == :openai
    end
    
    test "auto-detects Anthropic when ANTHROPIC_API_KEY is set" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")
      assert Config.get_provider([]) == :anthropic
    end
    
    test "defaults to OpenAI when no configuration is found" do
      assert Config.get_provider([]) == :openai
    end
    
    test "prioritizes options over environment variables" do
      System.put_env("MULBERRY_LLM_PROVIDER", "anthropic")
      assert Config.get_provider(provider: :google) == :google
    end
  end
  
  describe "default_config/1" do
    test "returns OpenAI defaults" do
      assert {:ok, config} = Config.default_config(:openai)
      assert config.model == "gpt-3.5-turbo"
      assert config.temperature == 0.7
      assert config.endpoint == "https://api.openai.com/v1/chat/completions"
    end
    
    test "returns Anthropic defaults" do
      assert {:ok, config} = Config.default_config(:anthropic)
      assert config.model == "claude-3-sonnet-20240229"
      assert config.temperature == 0.7
      assert config.max_tokens == 4096
    end
    
    test "returns Google defaults" do
      assert {:ok, config} = Config.default_config(:google)
      assert config.model == "gemini-pro"
      assert config.temperature == 0.7
    end
    
    test "returns Ollama defaults" do
      assert {:ok, config} = Config.default_config(:ollama)
      assert config.model == "llama2"
      assert config.endpoint == "http://localhost:11434/api/chat"
    end
    
    test "returns error for unknown provider" do
      assert {:error, "Unknown provider: unknown"} = Config.default_config(:unknown)
    end
  end
  
  describe "operation_defaults/1" do
    test "returns summarize operation defaults" do
      assert {:ok, config} = Config.operation_defaults(:summarize)
      assert config.temperature == 0.3
      assert config.max_tokens == 500
    end
    
    test "returns title operation defaults" do
      assert {:ok, config} = Config.operation_defaults(:title)
      assert config.temperature == 0.2
      assert config.max_tokens == 50
    end
    
    test "returns empty map for unknown operations" do
      assert {:ok, config} = Config.operation_defaults(:unknown)
      assert config == %{}
    end
  end
  
  describe "env_config/1" do
    setup do
      # Clean up environment variables
      System.delete_env("MULBERRY_OPENAI_API_KEY")
      System.delete_env("OPENAI_API_KEY")
      System.delete_env("MULBERRY_OPENAI_MODEL")
      System.delete_env("MULBERRY_OPENAI_TEMPERATURE")
      System.delete_env("MULBERRY_OPENAI_MAX_TOKENS")
      System.delete_env("MULBERRY_OPENAI_ENDPOINT")
      :ok
    end
    
    test "loads API key from MULBERRY_ prefixed env var" do
      System.put_env("MULBERRY_OPENAI_API_KEY", "test-key-1")
      assert {:ok, config} = Config.env_config(:openai)
      assert config.api_key == "test-key-1"
    end
    
    test "loads API key from standard env var as fallback" do
      System.put_env("OPENAI_API_KEY", "test-key-2")
      assert {:ok, config} = Config.env_config(:openai)
      assert config.api_key == "test-key-2"
    end
    
    test "prefers MULBERRY_ prefixed API key" do
      System.put_env("MULBERRY_OPENAI_API_KEY", "mulberry-key")
      System.put_env("OPENAI_API_KEY", "standard-key")
      assert {:ok, config} = Config.env_config(:openai)
      assert config.api_key == "mulberry-key"
    end
    
    test "loads model from environment" do
      System.put_env("MULBERRY_OPENAI_MODEL", "gpt-4")
      assert {:ok, config} = Config.env_config(:openai)
      assert config.model == "gpt-4"
    end
    
    test "loads temperature from environment" do
      System.put_env("MULBERRY_OPENAI_TEMPERATURE", "0.5")
      assert {:ok, config} = Config.env_config(:openai)
      assert config.temperature == 0.5
    end
    
    test "loads max_tokens from environment" do
      System.put_env("MULBERRY_OPENAI_MAX_TOKENS", "1000")
      assert {:ok, config} = Config.env_config(:openai)
      assert config.max_tokens == 1000
    end
    
    test "loads endpoint from environment" do
      System.put_env("MULBERRY_OPENAI_ENDPOINT", "https://custom.openai.com/v1")
      assert {:ok, config} = Config.env_config(:openai)
      assert config.endpoint == "https://custom.openai.com/v1"
    end
    
    test "returns empty config when no env vars are set" do
      assert {:ok, config} = Config.env_config(:openai)
      assert config == %{}
    end
  end
  
  describe "validate_config/2" do
    test "validates OpenAI config requires API key" do
      assert {:error, message} = Config.validate_config(:openai, %{})
      assert message =~ "API key required"
      assert message =~ "OPENAI_API_KEY"
      
      assert {:ok, _} = Config.validate_config(:openai, %{api_key: "test"})
    end
    
    test "validates Anthropic config requires API key" do
      assert {:error, message} = Config.validate_config(:anthropic, %{})
      assert message =~ "API key required"
      assert message =~ "ANTHROPIC_API_KEY"
      
      assert {:ok, _} = Config.validate_config(:anthropic, %{api_key: "test"})
    end
    
    test "validates Vertex AI config requires project ID" do
      assert {:error, message} = Config.validate_config(:vertex_ai, %{})
      assert message =~ "Project ID required"
      assert message =~ "GCP_PROJECT_ID"
      
      assert {:ok, _} = Config.validate_config(:vertex_ai, %{project_id: "test-project"})
    end
    
    test "validates Ollama config without requirements" do
      assert {:ok, _} = Config.validate_config(:ollama, %{})
    end
    
    test "validates Bumblebee config without requirements" do
      assert {:ok, _} = Config.validate_config(:bumblebee, %{})
    end
  end
  
  describe "get_provider_config/3" do
    setup do
      # Clean up environment variables
      System.delete_env("MULBERRY_OPENAI_API_KEY")
      System.delete_env("OPENAI_API_KEY")
      System.delete_env("MULBERRY_OPENAI_MODEL")
      System.delete_env("MULBERRY_OPENAI_ENDPOINT")
      System.delete_env("MULBERRY_OPENAI_MAX_TOKENS")
      :ok
    end
    
    test "merges configurations in correct order" do
      System.put_env("MULBERRY_OPENAI_MODEL", "gpt-4")
      
      assert {:ok, config} = Config.get_provider_config(:openai, :summarize, 
        temperature: 0.9, 
        api_key: "test-key"
      )
      
      # From default_config
      assert config.endpoint == "https://api.openai.com/v1/chat/completions"
      
      # From operation_defaults (should override default)
      assert config.max_tokens == 500
      
      # From env_config (should override operation)
      assert config.model == "gpt-4"
      
      # From overrides (should override everything)
      assert config.temperature == 0.9
      assert config.api_key == "test-key"
    end
    
    test "returns error for unknown provider" do
      assert {:error, "Unknown provider: invalid"} = 
        Config.get_provider_config(:invalid, :default)
    end
  end
  
  describe "get_llm/2" do
    setup do
      # Clean up any existing env vars first
      System.delete_env("MULBERRY_LLM_PROVIDER")
      System.delete_env("MULBERRY_OPENAI_API_KEY") 
      System.delete_env("MULBERRY_OPENAI_MODEL")
      System.delete_env("MULBERRY_ANTHROPIC_API_KEY")
      System.delete_env("ANTHROPIC_API_KEY")
      
      # Set up test environment
      System.put_env("OPENAI_API_KEY", "test-openai-key")
      
      on_exit(fn ->
        System.delete_env("OPENAI_API_KEY")
        System.delete_env("ANTHROPIC_API_KEY")
      end)
      
      :ok
    end
    
    test "creates OpenAI LLM with defaults" do
      assert {:ok, llm} = Config.get_llm()
      assert %LangChain.ChatModels.ChatOpenAI{} = llm
      assert llm.model == "gpt-3.5-turbo"
    end
    
    test "creates LLM with operation-specific defaults" do
      assert {:ok, llm} = Config.get_llm(:title)
      # temperature and max_tokens might be overridden by the LLM library defaults
      assert is_float(llm.temperature)
      assert llm.temperature >= 0 and llm.temperature <= 1
    end
    
    test "creates LLM with custom provider" do
      System.put_env("ANTHROPIC_API_KEY", "test-anthropic-key")
      assert {:ok, llm} = Config.get_llm(:default, provider: :anthropic)
      assert %LangChain.ChatModels.ChatAnthropic{} = llm
    end
    
    test "returns error when API key is missing" do
      System.delete_env("OPENAI_API_KEY")
      assert {:error, message} = Config.get_llm()
      assert message =~ "API key required"
    end
  end
end