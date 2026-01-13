defmodule Mulberry.Export.MarkdownTest do
  @moduledoc """
  Tests for the Markdown export module.
  """

  use ExUnit.Case, async: true

  alias Mulberry.Export.Markdown

  setup do
    temp_dir = System.tmp_dir!()
    test_dir = Path.join(temp_dir, "markdown_export_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(test_dir)
    on_exit(fn -> File.rm_rf!(test_dir) end)
    {:ok, test_dir: test_dir}
  end

  defp sample_result(overrides \\ %{}) do
    Map.merge(
      %{
        url: "https://example.com/page",
        title: "Test Page",
        description: "A test page",
        content: "<p>Test content</p>",
        crawled_at: DateTime.utc_now(),
        meta: %{}
      },
      overrides
    )
  end

  describe "export_individual/3" do
    test "exports results to individual files", %{test_dir: test_dir} do
      results = [
        sample_result(%{url: "https://example.com/page1", title: "Page 1"}),
        sample_result(%{url: "https://example.com/page2", title: "Page 2"})
      ]

      {:ok, stats} = Markdown.export_individual(results, test_dir)

      assert stats.written == 2
      assert stats.skipped == 0
      assert stats.errors == 0

      # Check files were created
      files = File.ls!(test_dir)
      assert length(files) == 2
    end

    test "respects filename_pattern option", %{test_dir: test_dir} do
      results = [sample_result(%{title: "My Custom Title"})]

      {:ok, _stats} = Markdown.export_individual(results, test_dir, filename_pattern: "title")

      files = File.ls!(test_dir)
      assert Enum.any?(files, &String.contains?(&1, "my-custom-title"))
    end

    test "adds frontmatter when add_metadata is true", %{test_dir: test_dir} do
      results = [sample_result()]

      {:ok, _stats} = Markdown.export_individual(results, test_dir, add_metadata: true)

      [file] = File.ls!(test_dir)
      content = File.read!(Path.join(test_dir, file))
      assert String.starts_with?(content, "---")
      assert String.contains?(content, "url:")
    end

    test "skips frontmatter when add_metadata is false", %{test_dir: test_dir} do
      results = [sample_result()]

      {:ok, _stats} = Markdown.export_individual(results, test_dir, add_metadata: false)

      [file] = File.ls!(test_dir)
      content = File.read!(Path.join(test_dir, file))
      refute String.starts_with?(content, "---")
    end

    test "respects overwrite_policy :skip", %{test_dir: test_dir} do
      results = [sample_result()]

      # First write
      {:ok, stats1} = Markdown.export_individual(results, test_dir, overwrite_policy: :skip)
      assert stats1.written == 1

      # Second write should skip
      {:ok, stats2} = Markdown.export_individual(results, test_dir, overwrite_policy: :skip)
      assert stats2.skipped == 1
      assert stats2.written == 0
    end

    test "respects overwrite_policy :overwrite", %{test_dir: test_dir} do
      results = [sample_result()]

      {:ok, _} = Markdown.export_individual(results, test_dir, overwrite_policy: :overwrite)
      {:ok, stats} = Markdown.export_individual(results, test_dir, overwrite_policy: :overwrite)

      assert stats.written == 1
      assert stats.skipped == 0
    end

    test "handles parallel writes", %{test_dir: test_dir} do
      # Create many results to test parallelism
      results = for i <- 1..20 do
        sample_result(%{
          url: "https://example.com/page#{i}",
          title: "Page #{i}"
        })
      end

      {:ok, stats} = Markdown.export_individual(results, test_dir, parallel: true)

      assert stats.written == 20
      assert length(File.ls!(test_dir)) == 20
    end

    test "calls progress callback", %{test_dir: test_dir} do
      results = [sample_result(), sample_result(%{url: "https://example.com/other"})]
      progress_calls = :ets.new(:progress_calls, [:set, :public])

      on_progress = fn index, total ->
        :ets.insert(progress_calls, {index, total})
      end

      {:ok, _stats} = Markdown.export_individual(results, test_dir,
        parallel: false,
        on_progress: on_progress
      )

      # Should have called progress for each file
      assert :ets.info(progress_calls, :size) == 2
    end
  end

  describe "export_combined/3" do
    test "exports results to combined file", %{test_dir: test_dir} do
      results = [
        sample_result(%{title: "Page 1"}),
        sample_result(%{url: "https://example.com/page2", title: "Page 2"})
      ]

      {:ok, filepath} = Markdown.export_combined(results, test_dir)

      assert String.ends_with?(filepath, "combined.md")
      assert File.exists?(filepath)

      content = File.read!(filepath)
      assert String.contains?(content, "# Crawl Results")
      assert String.contains?(content, "Page 1")
      assert String.contains?(content, "Page 2")
    end

    test "respects combined_filename option", %{test_dir: test_dir} do
      results = [sample_result()]

      {:ok, filepath} = Markdown.export_combined(results, test_dir, combined_filename: "all-pages")

      assert String.ends_with?(filepath, "all-pages.md")
    end

    test "includes TOC when add_metadata is true", %{test_dir: test_dir} do
      results = [
        sample_result(%{title: "First Page"}),
        sample_result(%{url: "https://example.com/second", title: "Second Page"})
      ]

      {:ok, filepath} = Markdown.export_combined(results, test_dir, add_metadata: true)

      content = File.read!(filepath)
      assert String.contains?(content, "Table of Contents")
      assert String.contains?(content, "[First Page]")
      assert String.contains?(content, "[Second Page]")
    end

    test "uses HTML anchors for TOC links", %{test_dir: test_dir} do
      results = [sample_result(%{title: "Test Title"})]

      {:ok, filepath} = Markdown.export_combined(results, test_dir)

      content = File.read!(filepath)
      assert String.contains?(content, "<a id=\"test-title\"></a>")
    end
  end

  describe "build_frontmatter/1" do
    test "generates valid YAML frontmatter" do
      result = sample_result()
      frontmatter = Markdown.build_frontmatter(result)

      assert String.starts_with?(frontmatter, "---\n")
      assert String.contains?(frontmatter, "url:")
      assert String.contains?(frontmatter, "title:")
      assert String.contains?(frontmatter, "crawled_at:")
    end

    test "escapes special YAML characters" do
      result = sample_result(%{
        url: "https://example.com/page?foo=bar",
        title: "Title: With Colon"
      })

      frontmatter = Markdown.build_frontmatter(result)

      # Title with colon should be quoted
      assert String.contains?(frontmatter, "\"Title: With Colon\"")
    end

    test "escapes newlines in values" do
      result = sample_result(%{title: "Title\nWith\nNewlines"})
      frontmatter = Markdown.build_frontmatter(result)

      # Should escape newlines
      assert String.contains?(frontmatter, "\\n")
      refute String.match?(frontmatter, ~r/title:.*\n.*With/)
    end
  end

  describe "generate_anchor/2" do
    test "generates URL-safe anchor" do
      assert "hello-world" = Markdown.generate_anchor("Hello World", 1)
    end

    test "handles special characters" do
      assert "test-page" = Markdown.generate_anchor("Test & Page!", 1)
    end

    test "falls back to page-N for empty result" do
      assert "page-5" = Markdown.generate_anchor("!!!", 5)
      assert "page-1" = Markdown.generate_anchor("", 1)
      assert "page-3" = Markdown.generate_anchor(nil, 3)
    end

    test "converts to lowercase" do
      assert "uppercase-title" = Markdown.generate_anchor("UPPERCASE TITLE", 1)
    end
  end

  describe "build_toc/1" do
    test "generates table of contents" do
      results = [
        sample_result(%{title: "First"}),
        sample_result(%{title: "Second"})
      ]

      toc = Markdown.build_toc(results)

      assert String.contains?(toc, "- [First](#first)")
      assert String.contains?(toc, "- [Second](#second)")
    end

    test "handles nil titles" do
      results = [sample_result(%{title: nil})]
      toc = Markdown.build_toc(results)

      assert String.contains?(toc, "- [Page 1](#page-1)")
    end
  end
end
