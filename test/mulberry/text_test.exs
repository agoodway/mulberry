defmodule Mulberry.TextTest do
  use ExUnit.Case, async: true
  use Mimic
  import ExUnit.CaptureLog
  doctest Mulberry.Text

  alias Mulberry.Text
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.Chains.LLMChain
  alias LangChain.Message

  describe "split/1" do
    test "splits text into chunks" do
      text = Faker.Lorem.paragraphs(5) |> Enum.join("\n\n")
      
      chunks = Text.split(text)
      
      assert is_list(chunks)
      assert length(chunks) > 0
      assert Enum.all?(chunks, &is_binary/1)
    end

    test "handles empty text" do
      assert Text.split("") == [""]
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
      assert tokens == []
    end

    test "handles text with numbers and special characters" do
      text = "The price is $42.50 for 3 items!"
      
      assert {:ok, tokens} = Text.tokens(text)
      assert is_list(tokens)
      assert length(tokens) > 0
    end

    test "returns error when tokenization fails" do
      # Mock tokenizer to simulate failure
      expect(Tokenizers.Tokenizer, :from_pretrained, fn _, _ -> {:error, :tokenizer_error} end)
      
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

    test "returns 0 for empty text" do
      assert {:ok, 0} = Text.token_count("")
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
      expect(ChatOpenAI, :new!, fn [] -> %ChatOpenAI{} end)
      expect(LLMChain, :new!, fn %{llm: %ChatOpenAI{}, verbose: false} -> %LLMChain{} end)
      expect(LLMChain, :add_messages, fn %LLMChain{}, messages -> 
        assert length(messages) == 2
        assert hd(messages).role == :system
        %LLMChain{messages: messages}
      end)
      expect(LLMChain, :run, fn %LLMChain{} -> 
        {:ok, %Message{role: :assistant, content: "This is a summary"}}
      end)
      
      assert {:ok, "This is a summary"} = Text.summarize(text)
    end

    test "summarizes with custom LLM" do
      text = Faker.Lorem.paragraph()
      custom_llm = %ChatOpenAI{model: "gpt-4"}
      
      expect(LLMChain, :new!, fn %{llm: ^custom_llm, verbose: false} -> %LLMChain{} end)
      expect(LLMChain, :add_messages, fn chain, _messages -> chain end)
      expect(LLMChain, :run, fn %LLMChain{} -> 
        {:ok, %Message{role: :assistant, content: "Custom summary"}}
      end)
      
      assert {:ok, "Custom summary"} = Text.summarize(text, llm: custom_llm)
    end

    test "summarizes with custom system message" do
      text = Faker.Lorem.paragraph()
      custom_message = "Summarize this in one sentence"
      
      expect(ChatOpenAI, :new!, fn [] -> %ChatOpenAI{} end)
      expect(LLMChain, :new!, fn _ -> %LLMChain{} end)
      expect(LLMChain, :add_messages, fn %LLMChain{}, messages -> 
        system_message = hd(messages)
        assert system_message.content == custom_message
        %LLMChain{messages: messages}
      end)
      expect(LLMChain, :run, fn _ -> 
        {:ok, %Message{role: :assistant, content: "One sentence summary"}}
      end)
      
      assert {:ok, "One sentence summary"} = Text.summarize(text, system_message: custom_message)
    end

    test "handles LLM errors" do
      text = Faker.Lorem.paragraph()
      
      expect(ChatOpenAI, :new!, fn [] -> %ChatOpenAI{} end)
      expect(LLMChain, :new!, fn _ -> %LLMChain{} end)
      expect(LLMChain, :add_messages, fn chain, _ -> chain end)
      expect(LLMChain, :run, fn _ -> {:error, "API error"} end)
      
      assert {:error, {:error, "API error"}} = Text.summarize(text)
    end
  end

  describe "title/2" do
    test "generates title with default options" do
      text = Faker.Lorem.paragraphs(2) |> Enum.join("\n\n")
      
      expect(ChatOpenAI, :new!, fn [] -> %ChatOpenAI{} end)
      expect(LLMChain, :new!, fn _ -> %LLMChain{} end)
      expect(LLMChain, :add_messages, fn %LLMChain{}, messages -> 
        assert length(messages) == 2
        assert hd(messages).role == :system
        %LLMChain{messages: messages}
      end)
      expect(LLMChain, :run, fn _ -> 
        {:ok, %Message{role: :assistant, content: "Generated Title"}}
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
      expect(LLMChain, :run, fn _ -> 
        {:ok, %Message{role: :assistant, content: "Catchy Title"}}
      end)
      
      assert {:ok, "Catchy Title"} = Text.title(text, 
        llm: custom_llm, 
        additional_messages: additional_messages
      )
    end

    test "handles empty text" do
      expect(ChatOpenAI, :new!, fn [] -> %ChatOpenAI{} end)
      expect(LLMChain, :new!, fn _ -> %LLMChain{} end)
      expect(LLMChain, :add_messages, fn chain, _ -> chain end)
      expect(LLMChain, :run, fn _ -> 
        {:ok, %Message{role: :assistant, content: "Empty Content"}}
      end)
      
      assert {:ok, "Empty Content"} = Text.title("")
    end
  end
end