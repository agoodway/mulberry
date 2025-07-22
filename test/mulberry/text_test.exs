defmodule Mulberry.TextTest do
  use ExUnit.Case, async: false
  use Mimic
  doctest Mulberry.Text

  alias Mulberry.Text
  alias Mulberry.LangChain.Config
  alias LangChain.ChatModels.{ChatOpenAI, ChatAnthropic}
  alias LangChain.Chains.LLMChain
  alias LangChain.Message
  
  setup do
    # Ensure environment is clean for tests
    System.put_env("OPENAI_API_KEY", "test-key")
    
    on_exit(fn ->
      System.delete_env("MULBERRY_LLM_PROVIDER")
      System.delete_env("MULBERRY_OPENAI_API_KEY")
      System.delete_env("MULBERRY_ANTHROPIC_API_KEY")
    end)
    
    :ok
  end

  describe "split/1" do
    test "splits text into chunks" do
      text = Faker.Lorem.paragraphs(5) |> Enum.join("\n\n")
      
      chunks = Text.split(text)
      
      assert is_list(chunks)
      assert length(chunks) > 0
      assert Enum.all?(chunks, &is_binary/1)
    end

    test "handles empty text" do
      # TextChunker returns a special message for empty text
      assert Text.split("") == ["incompatible_config_or_text_no_chunks_saved"]
    end

    test "handles single word" do
      word = Faker.Lorem.word()
      assert Text.split(word) == [word]
    end

    test "handles text with special characters" do
      text = "Hello! How are you? I'm fine, thanks."
      chunks = Text.split(text)
      
      assert is_list(chunks)
      assert Enum.all?(chunks, &is_binary/1)
    end
  end

  describe "tokens/1" do
    test "tokenizes text into tokens" do
      text = Faker.Lorem.sentence()
      
      result = Text.tokens(text)
      
      assert {:ok, tokens} = result
      assert is_list(tokens)
      assert length(tokens) > 0
      assert Enum.all?(tokens, &is_binary/1)
    end

    test "handles empty text" do
      assert {:ok, tokens} = Text.tokens("")
      # BERT tokenizer adds special tokens even for empty text
      assert tokens == ["[CLS]", "[SEP]"]
    end

    test "handles text with numbers and special characters" do
      text = "The price is $42.50 for 3 items!"
      
      assert {:ok, tokens} = Text.tokens(text)
      assert is_list(tokens)
      assert length(tokens) > 0
    end

    test "returns error when tokenization fails" do
      # Mock tokenizer to simulate failure
      expect(Tokenizers.Tokenizer, :from_pretrained, fn "bert-base-cased" -> {:error, :tokenizer_error} end)
      
      assert {:error, :tokenization_failed} = Text.tokens("test")
    end
  end

  describe "token_count/1" do
    test "counts tokens in text" do
      text = Faker.Lorem.sentence()
      
      result = Text.token_count(text)
      
      assert {:ok, count} = result
      assert is_integer(count)
      assert count > 0
    end

    test "returns 2 for empty text" do
      # BERT tokenizer adds [CLS] and [SEP] tokens even for empty text
      assert {:ok, 2} = Text.token_count("")
    end

    test "counts tokens in long text" do
      text = Faker.Lorem.paragraphs(3) |> Enum.join(" ")
      
      assert {:ok, count} = Text.token_count(text)
      assert count > 10  # Longer text should have more tokens
    end
  end

  describe "summarize/2" do
    test "summarizes text with default options" do
      text = Faker.Lorem.paragraphs(3) |> Enum.join("\n\n")
      
      # Mock the LLM chain
      expect(Config, :get_llm, fn :summarize, _opts -> 
        {:ok, %ChatOpenAI{}}
      end)
      expect(LLMChain, :new!, fn %{llm: %ChatOpenAI{}, verbose: false} -> %LLMChain{} end)
      expect(LLMChain, :add_messages, fn %LLMChain{}, messages -> 
        assert length(messages) == 2
        assert hd(messages).role == :system
        %LLMChain{messages: messages}
      end)
      expect(LLMChain, :run, fn chain, _opts -> 
        {:ok, chain, %Message{role: :assistant, content: "This is a summary"}}
      end)
      
      assert {:ok, "This is a summary"} = Text.summarize(text)
    end

    test "summarizes with custom LLM" do
      text = Faker.Lorem.paragraph()
      custom_llm = %ChatOpenAI{model: "gpt-4"}
      
      expect(LLMChain, :new!, fn %{llm: ^custom_llm, verbose: false} -> %LLMChain{} end)
      expect(LLMChain, :add_messages, fn chain, _messages -> chain end)
      expect(LLMChain, :run, fn chain, _opts -> 
        {:ok, chain, %Message{role: :assistant, content: "Custom summary"}}
      end)
      
      assert {:ok, "Custom summary"} = Text.summarize(text, llm: custom_llm)
    end

    test "summarizes with custom system message" do
      text = Faker.Lorem.paragraph()
      custom_message = "Summarize this in one sentence"
      
      expect(Config, :get_llm, fn :summarize, opts -> 
        assert opts[:system_message] == custom_message
        {:ok, %ChatOpenAI{}}
      end)
      expect(LLMChain, :new!, fn _ -> %LLMChain{} end)
      expect(LLMChain, :add_messages, fn %LLMChain{}, messages -> 
        system_message = hd(messages)
        assert system_message.content == custom_message
        %LLMChain{messages: messages}
      end)
      expect(LLMChain, :run, fn chain, _opts -> 
        {:ok, chain, %Message{role: :assistant, content: "One sentence summary"}}
      end)
      
      assert {:ok, "One sentence summary"} = Text.summarize(text, system_message: custom_message)
    end

    test "handles LLM errors" do
      text = Faker.Lorem.paragraph()
      
      expect(Config, :get_llm, fn :summarize, _opts -> 
        {:ok, %ChatOpenAI{}}
      end)
      expect(LLMChain, :new!, fn _ -> %LLMChain{} end)
      expect(LLMChain, :add_messages, fn chain, _ -> chain end)
      expect(LLMChain, :run, fn chain, _opts -> {:error, chain, "API error"} end)
      
      assert {:error, {:error, "API error"}} = Text.summarize(text)
    end
  end

  describe "title/2" do
    test "generates title with default options" do
      text = Faker.Lorem.paragraphs(2) |> Enum.join("\n\n")
      
      expect(Config, :get_llm, fn :title, _opts -> 
        {:ok, %ChatOpenAI{}}
      end)
      expect(LLMChain, :new!, fn _ -> %LLMChain{} end)
      expect(LLMChain, :add_messages, fn %LLMChain{}, messages -> 
        assert length(messages) == 2
        assert hd(messages).role == :system
        %LLMChain{messages: messages}
      end)
      expect(LLMChain, :run, fn chain, _opts -> 
        {:ok, chain, %Message{role: :assistant, content: "Generated Title"}}
      end)
      
      assert {:ok, "Generated Title"} = Text.title(text)
    end

    test "generates title with custom options" do
      text = Faker.Lorem.paragraph()
      custom_llm = %ChatOpenAI{model: "gpt-4"}
      additional_messages = [Message.new_user!("Make it catchy")]
      
      expect(LLMChain, :new!, fn %{llm: ^custom_llm} -> %LLMChain{} end)
      expect(LLMChain, :add_messages, fn %LLMChain{}, messages -> 
        assert length(messages) == 3  # system + additional + user
        %LLMChain{messages: messages}
      end)
      expect(LLMChain, :run, fn chain, _opts -> 
        {:ok, chain, %Message{role: :assistant, content: "Catchy Title"}}
      end)
      
      assert {:ok, "Catchy Title"} = Text.title(text, 
        llm: custom_llm, 
        additional_messages: additional_messages
      )
    end

    test "handles empty text" do
      expect(Config, :get_llm, fn :title, _opts -> 
        {:ok, %ChatOpenAI{}}
      end)
      expect(LLMChain, :new!, fn _ -> %LLMChain{} end)
      expect(LLMChain, :add_messages, fn chain, _ -> chain end)
      expect(LLMChain, :run, fn chain, _opts -> 
        {:ok, chain, %Message{role: :assistant, content: "Empty Content"}}
      end)
      
      assert {:ok, "Empty Content"} = Text.title("")
    end
  end
  
  describe "summarize/2 with new config system" do
    test "uses default provider when no options specified" do
      text = Faker.Lorem.paragraph()
      
      # Mock Config.get_llm to verify it's called
      expect(Config, :get_llm, fn :summarize, _opts -> 
        {:ok, %ChatOpenAI{model: "gpt-3.5-turbo"}}
      end)
      
      expect(LLMChain, :new!, fn _ -> %LLMChain{} end)
      expect(LLMChain, :add_messages, fn chain, _ -> chain end)
      expect(LLMChain, :run, fn chain, _opts -> 
        {:ok, chain, %{content: "Summary"}}
      end)
      
      assert {:ok, "Summary"} = Text.summarize(text)
    end
    
    test "uses specified provider from options" do
      text = Faker.Lorem.paragraph()
      System.put_env("ANTHROPIC_API_KEY", "test-anthropic-key")
      
      # Mock Config.get_llm to verify provider is passed
      expect(Config, :get_llm, fn :summarize, opts -> 
        assert opts[:provider] == :anthropic
        {:ok, %ChatAnthropic{model: "claude-3-sonnet-20240229"}}
      end)
      
      expect(LLMChain, :new!, fn _ -> %LLMChain{} end)
      expect(LLMChain, :add_messages, fn chain, _ -> chain end)
      expect(LLMChain, :run, fn chain, _opts -> 
        {:ok, chain, %{content: "Anthropic summary"}}
      end)
      
      assert {:ok, "Anthropic summary"} = Text.summarize(text, provider: :anthropic)
    end
    
    test "passes through configuration options" do
      text = Faker.Lorem.paragraph()
      
      expect(Config, :get_llm, fn :summarize, opts -> 
        assert opts[:temperature] == 0.5
        assert opts[:max_tokens] == 1000
        {:ok, %ChatOpenAI{temperature: 0.5, max_tokens: 1000}}
      end)
      
      expect(LLMChain, :new!, fn _ -> %LLMChain{} end)
      expect(LLMChain, :add_messages, fn chain, _ -> chain end)
      expect(LLMChain, :run, fn chain, _opts -> 
        {:ok, chain, %{content: "Custom config summary"}}
      end)
      
      assert {:ok, "Custom config summary"} = Text.summarize(text, 
        temperature: 0.5,
        max_tokens: 1000
      )
    end
    
    test "backward compatibility: accepts pre-configured llm" do
      text = Faker.Lorem.paragraph()
      custom_llm = %ChatOpenAI{model: "gpt-4"}
      
      # Config.get_llm should NOT be called when llm is provided
      reject(&Config.get_llm/2)
      
      expect(LLMChain, :new!, fn %{llm: ^custom_llm} -> %LLMChain{} end)
      expect(LLMChain, :add_messages, fn chain, _ -> chain end)
      expect(LLMChain, :run, fn chain, _opts -> 
        {:ok, chain, %{content: "Legacy summary"}}
      end)
      
      assert {:ok, "Legacy summary"} = Text.summarize(text, llm: custom_llm)
    end
    
    test "raises error when Config.get_llm fails" do
      text = Faker.Lorem.paragraph()
      System.delete_env("OPENAI_API_KEY")
      
      expect(Config, :get_llm, fn :summarize, _opts -> 
        {:error, "API key required"}
      end)
      
      assert_raise RuntimeError, ~r/Failed to create LLM/, fn ->
        Text.summarize(text)
      end
    end
  end
  
  describe "title/2 with new config system" do
    test "uses operation-specific configuration" do
      text = Faker.Lorem.paragraph()
      
      expect(Config, :get_llm, fn :title, _opts -> 
        {:ok, %ChatOpenAI{temperature: 0.2, max_tokens: 50}}
      end)
      
      expect(LLMChain, :new!, fn _ -> %LLMChain{} end)
      expect(LLMChain, :add_messages, fn chain, _ -> chain end)
      expect(LLMChain, :run, fn chain, _opts -> 
        {:ok, chain, %{content: "Short Title"}}
      end)
      
      assert {:ok, "Short Title"} = Text.title(text)
    end
    
    test "allows provider switching for title generation" do
      text = Faker.Lorem.paragraph()
      System.put_env("MULBERRY_LLM_PROVIDER", "anthropic")
      System.put_env("ANTHROPIC_API_KEY", "test-key")
      
      expect(Config, :get_llm, fn :title, opts -> 
        assert opts[:provider] == :google
        {:ok, %ChatOpenAI{}} # Mock as OpenAI for simplicity
      end)
      
      expect(LLMChain, :new!, fn _ -> %LLMChain{} end)
      expect(LLMChain, :add_messages, fn chain, _ -> chain end)
      expect(LLMChain, :run, fn chain, _opts -> 
        {:ok, chain, %{content: "Google Title"}}
      end)
      
      assert {:ok, "Google Title"} = Text.title(text, provider: :google)
    end
  end
end