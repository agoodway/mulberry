defmodule Mulberry.Chains.SummarizeDocumentChainTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Mulberry.Chains.SummarizeDocumentChain
  alias Mulberry.Document.WebPage
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.Chains.LLMChain
  alias LangChain.Message

  setup :verify_on_exit!

  describe "new/1" do
    test "creates a chain with valid configuration" do
      llm = %ChatOpenAI{model: "gpt-4"}

      assert {:ok, chain} =
               SummarizeDocumentChain.new(%{
                 llm: llm,
                 strategy: :map_reduce,
                 chunk_size: 2000,
                 chunk_overlap: 200
               })

      assert chain.llm == llm
      assert chain.strategy == :map_reduce
      assert chain.chunk_size == 2000
      assert chain.chunk_overlap == 200
    end

    test "returns error without required llm" do
      assert {:error, changeset} = SummarizeDocumentChain.new(%{})
      assert "can't be blank" in errors_on(changeset).llm
    end

    test "validates chunk_size is positive" do
      llm = %ChatOpenAI{model: "gpt-4"}

      assert {:error, changeset} =
               SummarizeDocumentChain.new(%{
                 llm: llm,
                 chunk_size: 0
               })

      assert "must be greater than 0" in errors_on(changeset).chunk_size
    end

    test "uses default values when not specified" do
      llm = %ChatOpenAI{model: "gpt-4"}

      assert {:ok, chain} = SummarizeDocumentChain.new(%{llm: llm})

      assert chain.strategy == :stuff
      assert chain.chunk_size == 1000
      assert chain.chunk_overlap == 100
      assert chain.max_chunks_per_group == 10
      assert chain.verbose == false
    end
  end

  describe "new!/1" do
    test "returns chain with valid configuration" do
      llm = %ChatOpenAI{model: "gpt-4"}

      chain = SummarizeDocumentChain.new!(%{llm: llm})

      assert chain.llm == llm
    end

    test "raises error with invalid configuration" do
      assert_raise LangChain.LangChainError, fn ->
        SummarizeDocumentChain.new!(%{})
      end
    end
  end

  describe "summarize_text/3" do
    setup do
      llm = %ChatOpenAI{model: "gpt-4", stream: false}
      {:ok, llm: llm}
    end

    test "summarizes text using stuff strategy", %{llm: llm} do
      chain = SummarizeDocumentChain.new!(%{llm: llm, strategy: :stuff})

      text = "This is a test document. It contains important information."

      # Mock the LLMChain behavior
      expect(LLMChain, :new!, fn %{llm: ^llm, verbose: false} ->
        %LLMChain{llm: llm}
      end)

      expect(LLMChain, :add_messages, fn chain, messages ->
        assert length(messages) == 1
        assert hd(messages).role == :user
        chain
      end)

      expect(LLMChain, :run, fn _chain, _opts ->
        {:ok, %LLMChain{}, %Message{content: "This is a summary of the document."}}
      end)

      assert {:ok, "This is a summary of the document."} =
               SummarizeDocumentChain.summarize_text(chain, text)
    end

    test "handles progress callbacks", %{llm: llm} do
      chain = SummarizeDocumentChain.new!(%{llm: llm, strategy: :stuff})

      text = "This is a test document."
      _progress_calls = []

      # Mock the LLMChain behavior
      expect(LLMChain, :new!, fn _ -> %LLMChain{llm: llm} end)
      expect(LLMChain, :add_messages, fn chain, _ -> chain end)

      expect(LLMChain, :run, fn _chain, _opts ->
        {:ok, %LLMChain{}, %Message{content: "Summary"}}
      end)

      on_progress = fn stage, info ->
        send(self(), {:progress, stage, info})
      end

      {:ok, _} = SummarizeDocumentChain.summarize_text(chain, text, on_progress: on_progress)

      assert_received {:progress, :chunks_created, %{count: _}}
    end

    test "handles map_reduce strategy", %{llm: llm} do
      chain = SummarizeDocumentChain.new!(%{llm: llm, strategy: :map_reduce})

      text = "First chunk of text. Second chunk of text. Third chunk of text."

      # Mock multiple LLMChain calls for map and reduce phases
      expect(LLMChain, :new!, 4, fn _ -> %LLMChain{llm: llm} end)
      expect(LLMChain, :add_messages, 4, fn chain, _ -> chain end)

      # Map phase - 3 chunks
      expect(LLMChain, :run, 3, fn _chain, _opts ->
        {:ok, %LLMChain{}, %Message{content: "Chunk summary"}}
      end)

      # Reduce phase - 1 call
      expect(LLMChain, :run, fn _chain, _opts ->
        {:ok, %LLMChain{}, %Message{content: "Final combined summary"}}
      end)

      assert {:ok, "Final combined summary"} =
               SummarizeDocumentChain.summarize_text(chain, text)
    end

    test "handles refine strategy", %{llm: llm} do
      chain = SummarizeDocumentChain.new!(%{llm: llm, strategy: :refine})

      text = "First chunk. Second chunk. Third chunk."

      # Initial summary
      expect(LLMChain, :new!, fn _ -> %LLMChain{llm: llm} end)
      expect(LLMChain, :add_messages, fn chain, _ -> chain end)

      expect(LLMChain, :run, fn _chain, _opts ->
        {:ok, %LLMChain{}, %Message{content: "Initial summary"}}
      end)

      # Refinements - 2 more chunks
      expect(LLMChain, :new!, 2, fn _ -> %LLMChain{llm: llm} end)
      expect(LLMChain, :add_messages, 2, fn chain, _ -> chain end)

      expect(LLMChain, :run, 2, fn _chain, _opts ->
        {:ok, %LLMChain{}, %Message{content: "Refined summary"}}
      end)

      assert {:ok, "Refined summary"} =
               SummarizeDocumentChain.summarize_text(chain, text)
    end
  end

  describe "summarize/3" do
    setup do
      llm = %ChatOpenAI{model: "gpt-4", stream: false}
      {:ok, llm: llm}
    end

    test "summarizes a document", %{llm: llm} do
      chain = SummarizeDocumentChain.new!(%{llm: llm})

      document =
        WebPage.new(%{
          url: "https://example.com",
          markdown: "This is the document content."
        })

      # Mock the LLMChain behavior
      expect(LLMChain, :new!, fn _ -> %LLMChain{llm: llm} end)
      expect(LLMChain, :add_messages, fn chain, _ -> chain end)

      expect(LLMChain, :run, fn _chain, _opts ->
        {:ok, %LLMChain{}, %Message{content: "Document summary"}}
      end)

      assert {:ok, "Document summary"} =
               SummarizeDocumentChain.summarize(chain, document, [])
    end

    test "returns error when document has no text", %{llm: llm} do
      chain = SummarizeDocumentChain.new!(%{llm: llm})

      document = WebPage.new(%{url: "https://example.com"})

      assert {:error, :not_loaded} =
               SummarizeDocumentChain.summarize(chain, document, [])
    end
  end

  # Helper function to extract errors from changeset
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
