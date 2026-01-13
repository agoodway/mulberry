defmodule Mulberry.Search.FileTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Mulberry.Search.File
  alias Mulberry.Document

  setup :verify_on_exit!

  describe "search/4" do
    test "searches by filename with default options" do
      # Mock file system operations
      expect(Path, :wildcard, fn path ->
        case path do
          "./**/*" ->
            [
              "./lib/mulberry.ex",
              "./lib/mulberry/search.ex",
              "./test/mulberry_test.exs",
              "./README.md",
              "./_build/test/lib/mulberry/ebin/mulberry.beam"
            ]

          _ ->
            []
        end
      end)

      expect(Elixir.File, :regular?, 5, fn path ->
        not String.contains?(path, ".beam")
      end)

      assert {:ok, %{"results" => results}} = File.search("mulberry", 10, mode: "filename")

      assert length(results) == 2
      assert Enum.all?(results, fn r -> String.contains?(r["path"], "mulberry") end)
      assert Enum.all?(results, fn r -> r["score"] > 0 end)
    end

    test "searches by content using ripgrep when available" do
      # Mock ripgrep availability
      expect(System, :cmd, fn "which", ["rg"] -> {"", 0} end)

      # Mock ripgrep execution
      ripgrep_output = """
      {"type":"match","data":{"path":{"text":"./lib/mulberry.ex"},"lines":{"text":"defmodule Mulberry do"},"line_number":1,"absolute_offset":0,"submatches":[{"match":{"text":"Mulberry"},"start":10,"end":18}]}}
      {"type":"match","data":{"path":{"text":"./lib/mulberry.ex"},"lines":{"text":"  @moduledoc \\"\\"\\"\\nMulberry is an AI package\\"\\"\\"\\""},"line_number":2,"absolute_offset":22,"submatches":[{"match":{"text":"Mulberry"},"start":16,"end":24}]}}
      {"type":"match","data":{"path":{"text":"./test/mulberry_test.exs"},"lines":{"text":"defmodule MulberryTest do"},"line_number":1,"absolute_offset":0,"submatches":[{"match":{"text":"Mulberry"},"start":10,"end":18}]}}
      """

      expect(System, :cmd, fn "rg", args, opts ->
        assert "--json" in args
        assert "mulberry" in args
        assert opts == [stderr_to_stdout: true]
        {ripgrep_output, 0}
      end)

      assert {:ok, %{"results" => results}} = File.search("mulberry", 10, mode: "content")

      assert length(results) == 2
      assert Enum.any?(results, fn r -> r["path"] == "./lib/mulberry.ex" end)
      assert Enum.any?(results, fn r -> r["path"] == "./test/mulberry_test.exs" end)
      assert Enum.all?(results, fn r -> is_float(r["score"]) and r["score"] > 0 end)
      assert Enum.all?(results, fn r -> is_list(r["matches"]) and length(r["matches"]) > 0 end)
    end

    test "falls back to grep when ripgrep is not available" do
      # Mock ripgrep not available
      expect(System, :cmd, fn "which", ["rg"] -> {"", 1} end)

      # Mock file system
      expect(Path, :wildcard, fn "./**/*" -> ["./lib/mulberry.ex"] end)
      expect(Elixir.File, :regular?, fn _ -> true end)
      expect(Elixir.File, :stat, fn _ -> {:ok, %{size: 1000}} end)

      # Mock grep execution
      expect(System, :cmd, fn "grep", ["-n", "-i", "mulberry", "./lib/mulberry.ex"], _ ->
        {"1:defmodule Mulberry do\n2:  @moduledoc \"\"\"\n3:Mulberry is an AI package\"\"\"", 0}
      end)

      assert {:ok, %{"results" => results}} = File.search("mulberry", 10, mode: "content")

      assert length(results) == 1
      assert hd(results)["path"] == "./lib/mulberry.ex"
      assert length(hd(results)["matches"]) == 3
    end

    test "searches with combined mode" do
      # Mock filename search
      # Mock filesystem operations
      stub(Path, :wildcard, fn _ -> ["./lib/mulberry.ex", "./README.md"] end)
      stub(Elixir.File, :regular?, fn _ -> true end)
      stub(Elixir.File, :stat, fn _ -> {:ok, %{size: 1000}} end)

      # Mock content search (ripgrep)
      expect(System, :cmd, fn "which", ["rg"] -> {"", 0} end)

      expect(System, :cmd, fn "rg", _, _ ->
        {~s({"type":"match","data":{"path":{"text":"./README.md"},"lines":{"text":"# Mulberry"},"line_number":1}}),
         0}
      end)

      assert {:ok, %{"results" => results}} = File.search("mulberry", 10, mode: "combined")

      # Should have results from both filename and content search
      assert length(results) >= 1
      assert Enum.any?(results, fn r -> r["path"] == "./lib/mulberry.ex" end)
    end

    test "respects search options" do
      expect(Path, :wildcard, fn path ->
        case path do
          "./lib/**/*.ex" -> ["./lib/mulberry.ex", "./lib/mulberry/search.ex"]
          "./test/**/*.ex" -> ["./test/mulberry_test.exs"]
          _ -> []
        end
      end)

      # Allow any number of File.regular? calls
      stub(Elixir.File, :regular?, fn _ -> true end)

      opts = [
        paths: ["./lib", "./test"],
        patterns: ["*.ex"],
        exclude: ["_build", "deps"]
      ]

      opts = Keyword.put(opts, :mode, "filename")
      assert {:ok, %{"results" => results}} = File.search("search", 10, opts)

      assert length(results) == 1
      assert hd(results)["path"] == "./lib/mulberry/search.ex"
    end

    test "excludes directories properly" do
      expect(Path, :wildcard, fn "./**/*" ->
        [
          "./lib/mulberry.ex",
          "./_build/test/lib/mulberry.ex",
          "./deps/some_dep/lib/mulberry.ex"
        ]
      end)

      expect(Elixir.File, :regular?, 3, fn _ -> true end)

      assert {:ok, %{"results" => results}} = File.search("mulberry", 10, mode: "filename")

      assert length(results) == 1
      assert hd(results)["path"] == "./lib/mulberry.ex"
      refute Enum.any?(results, fn r -> String.contains?(r["path"], "_build") end)
      refute Enum.any?(results, fn r -> String.contains?(r["path"], "deps") end)
    end

    test "returns error for invalid search mode" do
      assert {:error, "Invalid search mode. Must be one of: filename, content, combined"} =
               File.search("test", 10, mode: "invalid")
    end

    test "handles empty search results" do
      expect(Path, :wildcard, fn _ -> [] end)

      assert {:ok, %{"results" => []}} = File.search("nonexistent", 10, mode: "filename")
    end

    test "respects count limit" do
      files = for i <- 1..50, do: "./file#{i}.ex"

      expect(Path, :wildcard, fn _ -> files end)
      expect(Elixir.File, :regular?, 50, fn _ -> true end)

      assert {:ok, %{"results" => results}} = File.search("file", 20, mode: "filename")

      assert length(results) == 20
    end

    test "calculates filename scores correctly" do
      expect(Path, :wildcard, fn _ ->
        [
          "./exact_match.ex",
          "./contains_exact_match_here.ex",
          "./has_exact_and_match.ex",
          "./only_match.ex"
        ]
      end)

      expect(Elixir.File, :regular?, 4, fn _ -> true end)

      assert {:ok, %{"results" => results}} = File.search("exact match", 10, mode: "filename")

      # Results should be sorted by score
      scores = Enum.map(results, fn r -> r["score"] end)
      assert scores == Enum.sort(scores, :desc)

      # Exact match should have highest score
      # Exact match (with underscore) should have highest score
      assert hd(results)["path"] == "./exact_match.ex"
      assert hd(results)["score"] == 1.0
    end
  end

  describe "to_documents/1" do
    test "converts search results to Document.File structs" do
      results = %{
        "results" => [
          %{
            "path" => "./lib/mulberry.ex",
            "score" => 0.9,
            "matches" => ["defmodule Mulberry do"],
            "preview" => "L1: defmodule Mulberry do"
          },
          %{
            "path" => "./test/test.ex",
            "score" => 0.5,
            "matches" => [],
            "preview" => nil
          }
        ]
      }

      assert {:ok, documents} = File.to_documents(results)

      assert length(documents) == 2
      assert Enum.all?(documents, fn doc -> %Document.File{} = doc end)

      [doc1, doc2] = documents
      assert doc1.path == "./lib/mulberry.ex"
      assert doc1.title == "mulberry.ex"
      assert Keyword.get(doc1.meta, :score) == 0.9

      assert doc2.path == "./test/test.ex"
      assert doc2.title == "test.ex"
    end

    test "handles empty results" do
      assert {:ok, []} = File.to_documents(%{"results" => []})
      assert {:ok, []} = File.to_documents([])
    end

    test "handles direct list of results" do
      results = [
        %{
          "path" => "./file1.ex",
          "score" => 0.8,
          "matches" => ["match"],
          "preview" => "preview"
        }
      ]

      assert {:ok, [doc]} = File.to_documents(results)
      assert doc.path == "./file1.ex"
    end

    test "returns error for invalid results format" do
      assert {:error, :invalid_search_results} = File.to_documents("invalid")
      assert {:error, :invalid_search_results} = File.to_documents(%{})
      assert {:error, :invalid_search_results} = File.to_documents(nil)
    end
  end

  describe "integration scenarios" do
    test "searching for Elixir modules" do
      expect(Path, :wildcard, fn _ ->
        ["./lib/my_app.ex", "./lib/my_app/worker.ex", "./lib/my_app/supervisor.ex"]
      end)

      expect(Elixir.File, :regular?, 3, fn _ -> true end)

      assert {:ok, %{"results" => results}} =
               File.search("supervisor", 10, mode: "filename", patterns: ["*.ex"])

      assert length(results) == 1
      assert hd(results)["path"] == "./lib/my_app/supervisor.ex"
    end

    test "searching documentation files" do
      expect(Path, :wildcard, fn path ->
        case path do
          "./**/*.md" -> ["./README.md", "./docs/guide.md", "./docs/api.md"]
          _ -> []
        end
      end)

      expect(Elixir.File, :regular?, 3, fn _ -> true end)

      assert {:ok, %{"results" => results}} =
               File.search("guide", 10, mode: "filename", patterns: ["*.md"])

      assert Enum.any?(results, fn r -> r["path"] == "./docs/guide.md" end)
    end

    test "searching with multiple patterns" do
      expect(Path, :wildcard, fn path ->
        case path do
          "./**/*.ex" -> ["./lib/app.ex"]
          "./**/*.exs" -> ["./test/app_test.exs"]
          _ -> []
        end
      end)

      expect(Elixir.File, :regular?, 2, fn _ -> true end)

      assert {:ok, %{"results" => results}} =
               File.search("app", 10, mode: "filename", patterns: ["*.ex", "*.exs"])

      assert length(results) == 2
      assert Enum.any?(results, fn r -> String.ends_with?(r["path"], ".ex") end)
      assert Enum.any?(results, fn r -> String.ends_with?(r["path"], ".exs") end)
    end
  end
end
