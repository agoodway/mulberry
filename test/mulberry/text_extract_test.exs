defmodule Mulberry.TextExtractTest do
  use ExUnit.Case, async: true
  use Mimic
  alias Mulberry.Text
  alias Mulberry.LangChain.Config
  alias Mulberry.Chains.DataExtractionChain

  describe "extract/2" do
    test "extracts structured data from text with schema" do
      # Mock the Config.get_llm call
      mock_llm = %{id: "mock_llm"}
      stub(Config, :get_llm, fn :extract, _opts -> {:ok, mock_llm} end)

      # Mock the DataExtractionChain.run call
      expected_data = [
        %{"name" => "Alice", "age" => 30, "city" => "New York"},
        %{"name" => "Bob", "age" => 25, "city" => "San Francisco"}
      ]

      stub(DataExtractionChain, :run, fn ^mock_llm, _schema, _text, _opts ->
        {:ok, expected_data}
      end)

      schema = %{
        type: "object",
        properties: %{
          name: %{type: "string"},
          age: %{type: "number"},
          city: %{type: "string"}
        }
      }

      text = "Alice is 30 years old and lives in New York. Bob, age 25, is from San Francisco."

      assert {:ok, result} = Text.extract(text, schema: schema)
      assert result == expected_data
    end

    test "raises error when schema is not provided" do
      assert_raise ArgumentError, ~r/You must provide :schema option/, fn ->
        Text.extract("some text")
      end
    end

    test "uses provided LLM instance when given" do
      custom_llm = %{id: "custom_llm"}

      stub(DataExtractionChain, :run, fn ^custom_llm, _schema, _text, _opts ->
        {:ok, [%{"test" => "data"}]}
      end)

      schema = %{type: "object", properties: %{test: %{type: "string"}}}

      assert {:ok, [%{"test" => "data"}]} = Text.extract("text", schema: schema, llm: custom_llm)
    end

    test "passes custom system message to chain" do
      mock_llm = %{id: "mock_llm"}
      stub(Config, :get_llm, fn :extract, _opts -> {:ok, mock_llm} end)

      custom_message = "Only extract verified data"

      stub(DataExtractionChain, :run, fn ^mock_llm, _schema, _text, opts ->
        assert opts[:system_message] == custom_message
        {:ok, []}
      end)

      schema = %{type: "object", properties: %{}}

      Text.extract("text", schema: schema, system_message: custom_message)
    end

    test "passes verbose flag to chain" do
      mock_llm = %{id: "mock_llm"}
      stub(Config, :get_llm, fn :extract, _opts -> {:ok, mock_llm} end)

      stub(DataExtractionChain, :run, fn ^mock_llm, _schema, _text, opts ->
        assert opts[:verbose] == true
        {:ok, []}
      end)

      schema = %{type: "object", properties: %{}}

      Text.extract("text", schema: schema, verbose: true)
    end

    test "handles extraction errors properly" do
      mock_llm = %{id: "mock_llm"}
      stub(Config, :get_llm, fn :extract, _opts -> {:ok, mock_llm} end)

      stub(DataExtractionChain, :run, fn ^mock_llm, _schema, _text, _opts ->
        {:error, :extraction_failed}
      end)

      schema = %{type: "object", properties: %{}}

      assert {:error, :extraction_failed} = Text.extract("text", schema: schema)
    end

    test "raises when LLM creation fails" do
      stub(Config, :get_llm, fn :extract, _opts -> {:error, :no_api_key} end)

      schema = %{type: "object", properties: %{}}

      assert_raise RuntimeError, ~r/Failed to create LLM:.*no_api_key/, fn ->
        Text.extract("text", schema: schema)
      end
    end

    test "supports provider-specific LLM configuration" do
      mock_llm = %{provider: :openai}

      stub(Config, :get_llm, fn :extract, opts ->
        assert opts[:provider] == :openai
        assert opts[:model] == "gpt-4"
        assert opts[:temperature] == 0.0
        {:ok, mock_llm}
      end)

      stub(DataExtractionChain, :run, fn ^mock_llm, _schema, _text, _opts ->
        {:ok, []}
      end)

      schema = %{type: "object", properties: %{}}

      Text.extract("text",
        schema: schema,
        provider: :openai,
        model: "gpt-4",
        temperature: 0.0
      )
    end
  end
end
