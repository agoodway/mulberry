defmodule Mix.Tasks.TextTest do
  use ExUnit.Case, async: false
  use Mimic

  import ExUnit.CaptureIO
  alias Mix.Tasks.Text
  alias Mulberry.Text, as: MulberryText

  setup do
    # Create a temporary test file
    test_file = Path.join(System.tmp_dir!(), "test_text_#{:rand.uniform(10000)}.txt")
    File.write!(test_file, "This is test content from a file.")
    
    on_exit(fn ->
      File.rm(test_file)
    end)
    
    {:ok, test_file: test_file}
  end

  describe "summarize operation" do
    test "summarizes text from --text argument" do
      text = Faker.Lorem.paragraphs(3) |> Enum.join("\n\n")
      summary = Faker.Lorem.sentence()

      expect(MulberryText, :summarize, fn ^text, _opts ->
        {:ok, summary}
      end)

      output = capture_io(fn ->
        Text.run(["summarize", "--text", text])
      end)

      assert output =~ "Generating summary..."
      assert output =~ "Summary: #{summary}"
    end

    test "summarizes text from file", %{test_file: test_file} do
      summary = "File content summary"

      expect(MulberryText, :summarize, fn "This is test content from a file.", _opts ->
        {:ok, summary}
      end)

      output = capture_io(fn ->
        Text.run(["summarize", "--file", test_file])
      end)

      assert output =~ "Summary: #{summary}"
    end

    test "passes provider and model options" do
      text = "Test text"

      expect(MulberryText, :summarize, fn ^text, opts ->
        assert opts[:provider] == :anthropic
        assert opts[:model] == "claude-3"
        {:ok, "Summary"}
      end)

      capture_io(fn ->
        Text.run(["summarize", "--text", text, "--provider", "anthropic", "--model", "claude-3"])
      end)
    end

    test "handles summarization errors" do
      expect(MulberryText, :summarize, fn _, _ ->
        {:error, "API error"}
      end)

      assert_raise Mix.Error, ~r/Failed to generate summary/, fn ->
        capture_io(fn ->
          Text.run(["summarize", "--text", "test"])
        end)
      end
    end
  end

  describe "title operation" do
    test "generates title with default options" do
      text = Faker.Lorem.paragraph()
      title = Faker.Lorem.sentence(3)

      expect(MulberryText, :title, fn ^text, _opts ->
        {:ok, title}
      end)

      output = capture_io(fn ->
        Text.run(["title", "--text", text])
      end)

      assert output =~ "Generating title..."
      assert output =~ "Title: #{title}"
    end

    test "passes max_words and fallback_title options" do
      text = "Test"

      expect(MulberryText, :title, fn ^text, opts ->
        assert opts[:max_words] == 5
        assert opts[:fallback_title] == "Default Title"
        {:ok, "Short Title"}
      end)

      capture_io(fn ->
        Text.run(["title", "--text", text, "--max-words", "5", "--fallback-title", "Default Title"])
      end)
    end
  end

  describe "classify operation" do
    test "classifies text with required categories" do
      text = "Technology article"
      categories = ["Tech", "Business", "Health"]

      expect(MulberryText, :classify, fn ^text, opts ->
        assert opts[:categories] == categories
        {:ok, "Tech"}
      end)

      output = capture_io(fn ->
        Text.run(["classify", "--text", text, "--categories", "Tech,Business,Health"])
      end)

      assert output =~ "Classifying into categories:"
      assert output =~ "Category: Tech"
    end

    test "requires categories parameter" do
      assert_raise Mix.Error, ~r/You must provide --categories/, fn ->
        capture_io(fn ->
          Text.run(["classify", "--text", "test"])
        end)
      end
    end

    test "parses examples JSON correctly" do
      text = "Test"
      examples_json = ~s([{"text":"iPhone","category":"Tech"},{"text":"Earnings","category":"Business"}])

      expect(MulberryText, :classify, fn ^text, opts ->
        assert opts[:examples] == [{"iPhone", "Tech"}, {"Earnings", "Business"}]
        {:ok, "Tech"}
      end)

      capture_io(fn ->
        Text.run(["classify", "--text", text, "--categories", "Tech,Business", "--examples", examples_json])
      end)
    end

    test "handles invalid examples JSON" do
      assert_raise Mix.Error, ~r/Invalid JSON/, fn ->
        capture_io(fn ->
          Text.run(["classify", "--text", "test", "--categories", "A,B", "--examples", "invalid json"])
        end)
      end
    end
  end

  describe "split operation" do
    test "splits text into chunks" do
      text = Faker.Lorem.paragraphs(5) |> Enum.join("\n\n")
      chunks = ["Chunk 1", "Chunk 2", "Chunk 3"]

      expect(MulberryText, :split, fn ^text ->
        chunks
      end)

      output = capture_io(fn ->
        Text.run(["split", "--text", text])
      end)

      assert output =~ "Splitting text into chunks..."
      assert output =~ "Text split into 3 chunks:"
      assert output =~ "Chunk 1"
      assert output =~ "Chunk 2"
      assert output =~ "Chunk 3"
    end

    test "outputs JSON format when requested" do
      text = "Test text"
      chunks = ["Part 1", "Part 2"]

      expect(MulberryText, :split, fn ^text ->
        chunks
      end)

      output = capture_io(fn ->
        Text.run(["split", "--text", text, "--output", "json"])
      end)

      # Extract JSON from output (skip the info messages)
      json_lines = output |> String.split("\n") |> Enum.drop_while(fn line -> !String.starts_with?(line, "{") end)
      json_output = Enum.join(json_lines, "\n")
      parsed = Jason.decode!(json_output)
      assert parsed["operation"] == "split"
      assert parsed["chunk_count"] == 2
      assert length(parsed["chunks"]) == 2
    end
  end

  describe "tokens operation" do
    test "counts tokens in text" do
      text = "Hello world"
      tokens = ["Hello", "world"]

      expect(MulberryText, :tokens, fn ^text ->
        {:ok, tokens}
      end)

      output = capture_io(fn ->
        Text.run(["tokens", "--text", text])
      end)

      assert output =~ "Tokenizing text..."
      assert output =~ "Token count: 2"
    end

    test "shows tokens with verbose flag" do
      text = "Test"
      tokens = ["Test", "token"]

      expect(MulberryText, :tokens, fn ^text ->
        {:ok, tokens}
      end)

      output = capture_io(fn ->
        Text.run(["tokens", "--text", text, "--verbose"])
      end)

      assert output =~ "Tokens:"
      assert output =~ ~s(["Test", "token"])
    end

    test "handles tokenization errors" do
      expect(MulberryText, :tokens, fn _ ->
        {:error, :tokenization_failed}
      end)

      assert_raise Mix.Error, ~r/Failed to tokenize/, fn ->
        capture_io(fn ->
          Text.run(["tokens", "--text", "test"])
        end)
      end
    end
  end

  describe "output options" do
    test "saves output to file", %{test_file: _} do
      output_file = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(10000)}.txt")
      
      expect(MulberryText, :title, fn _, _ ->
        {:ok, "Test Title"}
      end)

      output = capture_io(fn ->
        Text.run(["title", "--text", "test", "--save", output_file])
      end)

      assert output =~ "Output saved to: #{output_file}"
      assert File.exists?(output_file)
      assert File.read!(output_file) == "Test Title"
      
      File.rm!(output_file)
    end

    test "outputs JSON format" do
      expect(MulberryText, :title, fn _, _ ->
        {:ok, "JSON Title"}
      end)

      output = capture_io(fn ->
        Text.run(["title", "--text", "test", "--output", "json"])
      end)

      # Extract JSON from output (skip the info messages)
      json_lines = output |> String.split("\n") |> Enum.drop_while(fn line -> !String.starts_with?(line, "{") end)
      json_output = Enum.join(json_lines, "\n")
      parsed = Jason.decode!(json_output)
      assert parsed["operation"] == "title"
      assert parsed["result"] == "JSON Title"
    end
  end

  describe "error handling" do
    test "shows error for unknown operation" do
      assert_raise Mix.Error, ~r/Unknown operation: invalid/, fn ->
        capture_io(fn ->
          Text.run(["invalid", "--text", "test"])
        end)
      end
    end

    test "requires text or file input" do
      assert_raise Mix.Error, ~r/You must provide either --text or --file/, fn ->
        capture_io(fn ->
          Text.run(["summarize"])
        end)
      end
    end

    test "handles file not found error" do
      assert_raise Mix.Error, ~r/Error:/, fn ->
        capture_io(fn ->
          Text.run(["summarize", "--file", "/nonexistent/file.txt"])
        end)
      end
    end
  end

  describe "aliases" do
    test "supports short aliases" do
      expect(MulberryText, :title, fn "test", _opts ->
        {:ok, "Title"}
      end)

      output = capture_io(fn ->
        Text.run(["title", "-t", "test"])
      end)

      assert output =~ "Title: Title"
    end
  end
end