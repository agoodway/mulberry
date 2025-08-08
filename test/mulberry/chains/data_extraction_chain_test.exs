defmodule Mulberry.Chains.DataExtractionChainTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Mulberry.Chains.DataExtractionChain
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.Chains.LLMChain
  alias LangChain.Message
  alias LangChain.Function

  setup :verify_on_exit!

  describe "new/1 and new!/1" do
    test "creates a new chain with valid attributes" do
      attrs = %{
        llm: %{},
        schema: %{type: "object"},
        text: "Some text",
        verbose: false
      }

      assert {:ok, chain} = DataExtractionChain.new(attrs)
      assert chain.llm == %{}
      assert chain.schema == %{type: "object"}
      assert chain.text == "Some text"
      assert chain.verbose == false
    end

    test "requires llm, schema, and text" do
      assert {:error, changeset} = DataExtractionChain.new(%{})
      errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
      assert "can't be blank" in errors[:llm]
      assert "can't be blank" in errors[:schema]
      assert "can't be blank" in errors[:text]
    end

    test "new! raises on invalid attributes" do
      assert_raise RuntimeError, ~r/Invalid DataExtractionChain/, fn ->
        DataExtractionChain.new!(%{})
      end
    end
  end

  describe "run/4" do
    setup do
      llm = %ChatOpenAI{model: "gpt-3.5-turbo", stream: false}
      
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "number"},
          "occupation" => %{"type" => "string"}
        },
        "required" => ["name"]
      }
      
      {:ok, llm: llm, schema: schema}
    end

    test "successfully extracts data from text", %{llm: llm, schema: schema} do
      text = "John Smith is 32 years old and works as an engineer."
      
      # Mock the LLMChain creation and execution
      expect(LLMChain, :new!, fn %{llm: ^llm, verbose: false} ->
        %LLMChain{llm: llm, messages: [], tools: [], verbose: false}
      end)
      
      expect(LLMChain, :add_messages, fn chain, messages ->
        assert length(messages) == 2
        assert [system_msg, user_msg] = messages
        assert system_msg.role == :system
        assert user_msg.role == :user
        assert String.contains?(user_msg.content, text)
        %{chain | messages: messages}
      end)
      
      expect(LLMChain, :add_tools, fn chain, tools ->
        assert length(tools) == 1
        assert [%Function{name: "information_extraction"}] = tools
        %{chain | tools: tools}
      end)
      
      expect(LLMChain, :run, fn chain ->
        # Simulate successful extraction with tool call
        tool_call = %{
          "function" => %{
            "arguments" => Jason.encode!(%{
              "data" => [
                %{
                  "name" => "John Smith",
                  "age" => 32,
                  "occupation" => "engineer"
                }
              ]
            })
          }
        }
        
        assistant_msg = %Message{
          role: :assistant,
          content: "",
          tool_calls: [tool_call]
        }
        
        updated_chain = %{chain | messages: chain.messages ++ [assistant_msg]}
        {:ok, updated_chain, assistant_msg}
      end)
      
      assert {:ok, extracted_data} = DataExtractionChain.run(llm, schema, text)
      assert length(extracted_data) == 1
      assert [%{"name" => "John Smith", "age" => 32, "occupation" => "engineer"}] = extracted_data
    end

    test "handles extraction with verbose mode", %{llm: llm, schema: schema} do
      text = "Jane Doe is a doctor."
      
      # Mock with verbose mode expectations
      expect(LLMChain, :new!, fn %{llm: ^llm, verbose: true} ->
        %LLMChain{llm: llm, messages: [], tools: [], verbose: true}
      end)
      
      expect(LLMChain, :add_messages, fn chain, messages ->
        %{chain | messages: messages}
      end)
      
      expect(LLMChain, :add_tools, fn chain, tools ->
        %{chain | tools: tools}
      end)
      
      expect(LLMChain, :run, fn chain ->
        tool_call = %{
          "function" => %{
            "arguments" => Jason.encode!(%{
              "data" => [%{"name" => "Jane Doe", "occupation" => "doctor"}]
            })
          }
        }
        
        assistant_msg = %Message{
          role: :assistant,
          content: "",
          tool_calls: [tool_call]
        }
        
        updated_chain = %{chain | messages: chain.messages ++ [assistant_msg]}
        {:ok, updated_chain, assistant_msg}
      end)
      
      assert {:ok, extracted_data} = DataExtractionChain.run(llm, schema, text, verbose: true)
      assert [%{"name" => "Jane Doe", "occupation" => "doctor"}] = extracted_data
    end

    test "handles extraction with custom system message", %{llm: llm, schema: schema} do
      text = "The product costs $50."
      custom_system_msg = "Extract pricing information from the text."
      
      expect(LLMChain, :new!, fn _ -> %LLMChain{llm: llm, messages: [], tools: []} end)
      
      expect(LLMChain, :add_messages, fn chain, messages ->
        assert [system_msg, _user_msg] = messages
        assert system_msg.content == custom_system_msg
        %{chain | messages: messages}
      end)
      
      expect(LLMChain, :add_tools, fn chain, tools ->
        %{chain | tools: tools}
      end)
      
      expect(LLMChain, :run, fn chain ->
        tool_call = %{
          "function" => %{
            "arguments" => Jason.encode!(%{"data" => []})
          }
        }
        
        assistant_msg = %Message{
          role: :assistant,
          content: "",
          tool_calls: [tool_call]
        }
        {:ok, %{chain | messages: chain.messages ++ [assistant_msg]}, assistant_msg}
      end)
      
      assert {:ok, []} = DataExtractionChain.run(llm, schema, text, system_message: custom_system_msg)
    end

    test "handles empty extraction results", %{llm: llm, schema: schema} do
      text = "This text has no relevant information."
      
      expect(LLMChain, :new!, fn _ -> %LLMChain{llm: llm, messages: [], tools: []} end)
      expect(LLMChain, :add_messages, fn chain, messages -> %{chain | messages: messages} end)
      expect(LLMChain, :add_tools, fn chain, tools -> %{chain | tools: tools} end)
      
      expect(LLMChain, :run, fn chain ->
        # Return assistant message with empty tool calls
        tool_call = %{
          "function" => %{
            "arguments" => Jason.encode!(%{"data" => []})
          }
        }
        
        assistant_msg = %Message{
          role: :assistant,
          content: "",
          tool_calls: [tool_call]
        }
        {:ok, %{chain | messages: chain.messages ++ [assistant_msg]}, assistant_msg}
      end)
      
      assert {:ok, []} = DataExtractionChain.run(llm, schema, text)
    end

    test "handles multiple extracted instances", %{llm: llm, schema: schema} do
      text = "John is 30 and works as a teacher. Jane is 25 and is a doctor."
      
      expect(LLMChain, :new!, fn _ -> %LLMChain{llm: llm, messages: [], tools: []} end)
      expect(LLMChain, :add_messages, fn chain, messages -> %{chain | messages: messages} end)
      expect(LLMChain, :add_tools, fn chain, tools -> %{chain | tools: tools} end)
      
      expect(LLMChain, :run, fn chain ->
        tool_call = %{
          "function" => %{
            "arguments" => Jason.encode!(%{
              "data" => [
                %{"name" => "John", "age" => 30, "occupation" => "teacher"},
                %{"name" => "Jane", "age" => 25, "occupation" => "doctor"}
              ]
            })
          }
        }
        
        assistant_msg = %Message{
          role: :assistant,
          content: "",
          tool_calls: [tool_call]
        }
        
        {:ok, %{chain | messages: chain.messages ++ [assistant_msg]}, assistant_msg}
      end)
      
      assert {:ok, extracted_data} = DataExtractionChain.run(llm, schema, text)
      assert length(extracted_data) == 2
      assert %{"name" => "John", "age" => 30, "occupation" => "teacher"} in extracted_data
      assert %{"name" => "Jane", "age" => 25, "occupation" => "doctor"} in extracted_data
    end

    test "handles LLM error responses", %{llm: llm, schema: schema} do
      text = "Some text"
      error_msg = "API rate limit exceeded"
      
      expect(LLMChain, :new!, fn _ -> %LLMChain{llm: llm, messages: [], tools: []} end)
      expect(LLMChain, :add_messages, fn chain, messages -> %{chain | messages: messages} end)
      expect(LLMChain, :add_tools, fn chain, tools -> %{chain | tools: tools} end)
      
      expect(LLMChain, :run, fn chain ->
        {:error, chain, error_msg}
      end)
      
      assert {:error, ^error_msg} = DataExtractionChain.run(llm, schema, text)
    end

    test "handles invalid JSON in tool call arguments", %{llm: llm, schema: schema} do
      text = "Some text"
      
      expect(LLMChain, :new!, fn _ -> %LLMChain{llm: llm, messages: [], tools: []} end)
      expect(LLMChain, :add_messages, fn chain, messages -> %{chain | messages: messages} end)
      expect(LLMChain, :add_tools, fn chain, tools -> %{chain | tools: tools} end)
      
      expect(LLMChain, :run, fn chain ->
        tool_call = %{
          "function" => %{
            "arguments" => "invalid json {{"
          }
        }
        
        assistant_msg = %Message{
          role: :assistant,
          content: "",
          tool_calls: [tool_call]
        }
        
        {:ok, %{chain | messages: chain.messages ++ [assistant_msg]}, assistant_msg}
      end)
      
      assert {:error, {:json_decode_error, _}} = DataExtractionChain.run(llm, schema, text)
    end

    test "uses Function struct as schema", %{llm: llm} do
      text = "Test text"
      
      # Create a Function struct as schema - must have a function field
      function = %Function{
        name: "custom_extract",
        description: "Custom extraction function",
        function: fn args, _context -> {:ok, args} end,
        parameters_schema: %{
          "type" => "object",
          "properties" => %{
            "field" => %{"type" => "string"}
          }
        }
      }
      
      expect(LLMChain, :new!, fn _ -> %LLMChain{llm: llm, messages: [], tools: []} end)
      expect(LLMChain, :add_messages, fn chain, messages -> %{chain | messages: messages} end)
      
      expect(LLMChain, :add_tools, fn chain, tools ->
        assert [tool] = tools
        # When passed a Function directly, it gets returned as-is
        assert tool == function
        %{chain | tools: tools}
      end)
      
      expect(LLMChain, :run, fn chain ->
        tool_call = %{
          "function" => %{
            "arguments" => Jason.encode!(%{"data" => []})
          }
        }
        
        assistant_msg = %Message{
          role: :assistant,
          content: "",
          tool_calls: [tool_call]
        }
        {:ok, %{chain | messages: chain.messages ++ [assistant_msg]}, assistant_msg}
      end)
      
      assert {:ok, []} = DataExtractionChain.run(llm, function, text)
    end

    test "rejects invalid schema type", %{llm: llm} do
      text = "Test text"
      invalid_schema = "not a map or Function"
      
      assert {:error, "Schema must be a map or Function struct"} = 
        DataExtractionChain.run(llm, invalid_schema, text)
    end
  end
end