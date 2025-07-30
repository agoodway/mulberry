defmodule Mulberry.Chains.DataExtractionChainTest do
  use ExUnit.Case, async: true
  alias Mulberry.Chains.DataExtractionChain

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

  # Integration tests would go here but require actual LLM setup
  # The run/4 function is tested through the Text.extract function tests
end