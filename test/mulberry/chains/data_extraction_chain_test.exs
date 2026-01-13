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
            "arguments" =>
              Jason.encode!(%{
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
            "arguments" =>
              Jason.encode!(%{
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

      assert {:ok, []} =
               DataExtractionChain.run(llm, schema, text, system_message: custom_system_msg)
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
            "arguments" =>
              Jason.encode!(%{
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

      # Use max_attempts: 1 to get immediate error without retry
      assert {:error, {:json_decode_error, _}} =
               DataExtractionChain.run(llm, schema, text, max_attempts: 1)
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

  describe "retry behavior" do
    import ExUnit.CaptureLog

    setup do
      llm = %ChatOpenAI{model: "gpt-3.5-turbo", stream: false}

      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "number"}
        },
        "required" => ["name", "age"]
      }

      {:ok, llm: llm, schema: schema}
    end

    defp setup_successful_extraction(data) do
      expect(LLMChain, :new!, fn _ -> %LLMChain{llm: %{}, messages: [], tools: []} end)
      expect(LLMChain, :add_messages, fn chain, messages -> %{chain | messages: messages} end)
      expect(LLMChain, :add_tools, fn chain, tools -> %{chain | tools: tools} end)

      expect(LLMChain, :run, fn chain ->
        tool_call = %{
          "function" => %{
            "arguments" => Jason.encode!(%{"data" => data})
          }
        }

        assistant_msg = %Message{
          role: :assistant,
          content: "",
          tool_calls: [tool_call]
        }

        {:ok, %{chain | messages: chain.messages ++ [assistant_msg]}, assistant_msg}
      end)
    end

    test "succeeds on first attempt when valid", %{llm: llm, schema: schema} do
      text = "John is 30 years old."
      valid_data = [%{"name" => "John", "age" => 30}]

      setup_successful_extraction(valid_data)

      assert {:ok, ^valid_data} = DataExtractionChain.run(llm, schema, text)
    end

    test "retries on schema validation failure and succeeds", %{llm: llm, schema: schema} do
      text = "John is 30 years old."
      invalid_data = [%{"name" => "John"}]
      valid_data = [%{"name" => "John", "age" => 30}]

      # First attempt - missing required field
      expect(LLMChain, :new!, fn _ -> %LLMChain{llm: %{}, messages: [], tools: []} end)
      expect(LLMChain, :add_messages, fn chain, messages -> %{chain | messages: messages} end)
      expect(LLMChain, :add_tools, fn chain, tools -> %{chain | tools: tools} end)

      expect(LLMChain, :run, fn chain ->
        tool_call = %{
          "function" => %{
            "arguments" => Jason.encode!(%{"data" => invalid_data})
          }
        }

        assistant_msg = %Message{role: :assistant, content: "", tool_calls: [tool_call]}
        {:ok, %{chain | messages: chain.messages ++ [assistant_msg]}, assistant_msg}
      end)

      # Second attempt - valid data, should have feedback in system message
      expect(LLMChain, :new!, fn _ -> %LLMChain{llm: %{}, messages: [], tools: []} end)

      expect(LLMChain, :add_messages, fn chain, messages ->
        [system_msg, _user_msg] = messages
        assert String.contains?(system_msg.content, "validation errors")
        assert String.contains?(system_msg.content, "missing required fields")
        %{chain | messages: messages}
      end)

      expect(LLMChain, :add_tools, fn chain, tools -> %{chain | tools: tools} end)

      expect(LLMChain, :run, fn chain ->
        tool_call = %{
          "function" => %{
            "arguments" => Jason.encode!(%{"data" => valid_data})
          }
        }

        assistant_msg = %Message{role: :assistant, content: "", tool_calls: [tool_call]}
        {:ok, %{chain | messages: chain.messages ++ [assistant_msg]}, assistant_msg}
      end)

      log =
        capture_log(fn ->
          assert {:ok, ^valid_data} =
                   DataExtractionChain.run(llm, schema, text, retry_delay_ms: 1)
        end)

      assert log =~ "failed validation"
    end

    test "returns max_attempts_exceeded after exhausting retries", %{llm: llm, schema: schema} do
      text = "John"
      invalid_data = [%{"name" => "John"}]

      # Set up 3 failed attempts (default max_attempts)
      for _ <- 1..3 do
        expect(LLMChain, :new!, fn _ -> %LLMChain{llm: %{}, messages: [], tools: []} end)
        expect(LLMChain, :add_messages, fn chain, messages -> %{chain | messages: messages} end)
        expect(LLMChain, :add_tools, fn chain, tools -> %{chain | tools: tools} end)

        expect(LLMChain, :run, fn chain ->
          tool_call = %{
            "function" => %{
              "arguments" => Jason.encode!(%{"data" => invalid_data})
            }
          }

          assistant_msg = %Message{role: :assistant, content: "", tool_calls: [tool_call]}
          {:ok, %{chain | messages: chain.messages ++ [assistant_msg]}, assistant_msg}
        end)
      end

      capture_log(fn ->
        assert {:error, {:max_attempts_exceeded, 3, errors}} =
                 DataExtractionChain.run(llm, schema, text, retry_delay_ms: 1)

        assert is_list(errors)
        assert length(errors) > 0
        assert Enum.any?(errors, &String.contains?(&1, "missing required fields"))
      end)
    end

    test "uses custom validator in addition to schema validation", %{llm: llm, schema: schema} do
      text = "John is 30."
      valid_schema_data = [%{"name" => "John", "age" => 30}]
      valid_all_data = [%{"name" => "John", "age" => 25}]

      # Custom validator that requires age < 30
      validator = fn results ->
        errors =
          results
          |> Enum.with_index()
          |> Enum.flat_map(fn {item, idx} ->
            if Map.get(item, "age", 0) >= 30 do
              ["Item #{idx}: age must be less than 30"]
            else
              []
            end
          end)

        if Enum.empty?(errors), do: {:ok, results}, else: {:error, errors}
      end

      # First attempt - passes schema but fails custom
      expect(LLMChain, :new!, fn _ -> %LLMChain{llm: %{}, messages: [], tools: []} end)
      expect(LLMChain, :add_messages, fn chain, messages -> %{chain | messages: messages} end)
      expect(LLMChain, :add_tools, fn chain, tools -> %{chain | tools: tools} end)

      expect(LLMChain, :run, fn chain ->
        tool_call = %{
          "function" => %{
            "arguments" => Jason.encode!(%{"data" => valid_schema_data})
          }
        }

        assistant_msg = %Message{role: :assistant, content: "", tool_calls: [tool_call]}
        {:ok, %{chain | messages: chain.messages ++ [assistant_msg]}, assistant_msg}
      end)

      # Second attempt - passes both
      expect(LLMChain, :new!, fn _ -> %LLMChain{llm: %{}, messages: [], tools: []} end)

      expect(LLMChain, :add_messages, fn chain, messages ->
        [system_msg, _user_msg] = messages
        assert String.contains?(system_msg.content, "age must be less than 30")
        %{chain | messages: messages}
      end)

      expect(LLMChain, :add_tools, fn chain, tools -> %{chain | tools: tools} end)

      expect(LLMChain, :run, fn chain ->
        tool_call = %{
          "function" => %{
            "arguments" => Jason.encode!(%{"data" => valid_all_data})
          }
        }

        assistant_msg = %Message{role: :assistant, content: "", tool_calls: [tool_call]}
        {:ok, %{chain | messages: chain.messages ++ [assistant_msg]}, assistant_msg}
      end)

      capture_log(fn ->
        assert {:ok, ^valid_all_data} =
                 DataExtractionChain.run(llm, schema, text,
                   validator: validator,
                   retry_delay_ms: 1
                 )
      end)
    end

    test "skips validation when validate: false", %{llm: llm, schema: schema} do
      text = "John"
      invalid_data = [%{"name" => "John"}]

      setup_successful_extraction(invalid_data)

      # Should succeed even though data is missing required field
      assert {:ok, ^invalid_data} =
               DataExtractionChain.run(llm, schema, text, validate: false)
    end

    test "single attempt mode (max_attempts: 1) skips retry", %{llm: llm, schema: schema} do
      text = "John"
      invalid_data = [%{"name" => "John"}]

      setup_successful_extraction(invalid_data)

      # Should return error without retry
      assert {:ok, ^invalid_data} =
               DataExtractionChain.run(llm, schema, text, max_attempts: 1)
    end

    test "retries on retryable LLM errors", %{llm: llm, schema: schema} do
      text = "John is 30."
      valid_data = [%{"name" => "John", "age" => 30}]

      # First attempt - JSON decode error (retryable)
      expect(LLMChain, :new!, fn _ -> %LLMChain{llm: %{}, messages: [], tools: []} end)
      expect(LLMChain, :add_messages, fn chain, messages -> %{chain | messages: messages} end)
      expect(LLMChain, :add_tools, fn chain, tools -> %{chain | tools: tools} end)

      expect(LLMChain, :run, fn chain ->
        tool_call = %{
          "function" => %{
            "arguments" => "invalid json {{"
          }
        }

        assistant_msg = %Message{role: :assistant, content: "", tool_calls: [tool_call]}
        {:ok, %{chain | messages: chain.messages ++ [assistant_msg]}, assistant_msg}
      end)

      # Second attempt - succeeds
      expect(LLMChain, :new!, fn _ -> %LLMChain{llm: %{}, messages: [], tools: []} end)
      expect(LLMChain, :add_messages, fn chain, messages -> %{chain | messages: messages} end)
      expect(LLMChain, :add_tools, fn chain, tools -> %{chain | tools: tools} end)

      expect(LLMChain, :run, fn chain ->
        tool_call = %{
          "function" => %{
            "arguments" => Jason.encode!(%{"data" => valid_data})
          }
        }

        assistant_msg = %Message{role: :assistant, content: "", tool_calls: [tool_call]}
        {:ok, %{chain | messages: chain.messages ++ [assistant_msg]}, assistant_msg}
      end)

      log =
        capture_log(fn ->
          assert {:ok, ^valid_data} =
                   DataExtractionChain.run(llm, schema, text, retry_delay_ms: 1)
        end)

      assert log =~ "retrying"
    end

    test "does not retry on non-retryable errors", %{llm: llm, schema: schema} do
      text = "John"
      error_msg = "API rate limit exceeded"

      expect(LLMChain, :new!, fn _ -> %LLMChain{llm: %{}, messages: [], tools: []} end)
      expect(LLMChain, :add_messages, fn chain, messages -> %{chain | messages: messages} end)
      expect(LLMChain, :add_tools, fn chain, tools -> %{chain | tools: tools} end)

      expect(LLMChain, :run, fn chain ->
        {:error, chain, error_msg}
      end)

      # Should fail immediately without retry
      assert {:error, ^error_msg} = DataExtractionChain.run(llm, schema, text)
    end

    test "respects custom max_attempts setting", %{llm: llm, schema: schema} do
      text = "John"
      invalid_data = [%{"name" => "John"}]

      # Set up 5 failed attempts (custom max_attempts)
      for _ <- 1..5 do
        expect(LLMChain, :new!, fn _ -> %LLMChain{llm: %{}, messages: [], tools: []} end)
        expect(LLMChain, :add_messages, fn chain, messages -> %{chain | messages: messages} end)
        expect(LLMChain, :add_tools, fn chain, tools -> %{chain | tools: tools} end)

        expect(LLMChain, :run, fn chain ->
          tool_call = %{
            "function" => %{
              "arguments" => Jason.encode!(%{"data" => invalid_data})
            }
          }

          assistant_msg = %Message{role: :assistant, content: "", tool_calls: [tool_call]}
          {:ok, %{chain | messages: chain.messages ++ [assistant_msg]}, assistant_msg}
        end)
      end

      capture_log(fn ->
        assert {:error, {:max_attempts_exceeded, 5, _errors}} =
                 DataExtractionChain.run(llm, schema, text,
                   max_attempts: 5,
                   retry_delay_ms: 1
                 )
      end)
    end
  end
end
