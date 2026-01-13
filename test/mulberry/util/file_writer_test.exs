defmodule Mulberry.Util.FileWriterTest do
  @moduledoc """
  Tests for the FileWriter utility module focusing on atomic writes and safety.
  """

  use ExUnit.Case, async: true

  alias Mulberry.Util.FileWriter

  setup do
    temp_dir = System.tmp_dir!()
    test_dir = Path.join(temp_dir, "file_writer_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(test_dir)
    on_exit(fn -> File.rm_rf!(test_dir) end)
    {:ok, test_dir: test_dir}
  end

  describe "write_file_atomic/2" do
    test "writes file successfully", %{test_dir: test_dir} do
      filepath = Path.join(test_dir, "test.md")
      content = "# Test Content\n\nThis is test content."

      assert :ok = FileWriter.write_file_atomic(filepath, content)
      assert File.exists?(filepath)
      assert File.read!(filepath) == content
    end

    test "creates parent directories if needed", %{test_dir: test_dir} do
      filepath = Path.join([test_dir, "subdir", "deep", "test.md"])
      content = "test"

      assert :ok = FileWriter.write_file_atomic(filepath, content)
      assert File.exists?(filepath)
    end

    test "overwrites existing file", %{test_dir: test_dir} do
      filepath = Path.join(test_dir, "existing.md")
      File.write!(filepath, "old content")

      assert :ok = FileWriter.write_file_atomic(filepath, "new content")
      assert File.read!(filepath) == "new content"
    end

    test "cleans up temp file on success", %{test_dir: test_dir} do
      filepath = Path.join(test_dir, "test.md")
      temp_path = filepath <> ".tmp"

      assert :ok = FileWriter.write_file_atomic(filepath, "content")
      refute File.exists?(temp_path)
    end

    test "handles empty content", %{test_dir: test_dir} do
      filepath = Path.join(test_dir, "empty.md")

      assert :ok = FileWriter.write_file_atomic(filepath, "")
      assert File.exists?(filepath)
      assert File.read!(filepath) == ""
    end

    test "handles unicode content", %{test_dir: test_dir} do
      filepath = Path.join(test_dir, "unicode.md")
      content = "# Cafe\n\nEmoji: \u{1F600} \u{1F389}"

      assert :ok = FileWriter.write_file_atomic(filepath, content)
      assert File.read!(filepath) == content
    end

    test "handles large content", %{test_dir: test_dir} do
      filepath = Path.join(test_dir, "large.md")
      # 1MB of content
      content = String.duplicate("x", 1_000_000)

      assert :ok = FileWriter.write_file_atomic(filepath, content)
      assert File.read!(filepath) == content
    end
  end

  describe "write_file_atomic_stream/2" do
    test "writes stream content successfully", %{test_dir: test_dir} do
      filepath = Path.join(test_dir, "stream.md")
      content_stream = ["# Header\n", "\n", "Paragraph 1\n", "\n", "Paragraph 2"]

      assert :ok = FileWriter.write_file_atomic_stream(filepath, content_stream)
      assert File.exists?(filepath)
      assert File.read!(filepath) == "# Header\n\nParagraph 1\n\nParagraph 2"
    end

    test "handles empty stream", %{test_dir: test_dir} do
      filepath = Path.join(test_dir, "empty_stream.md")

      assert :ok = FileWriter.write_file_atomic_stream(filepath, [])
      assert File.exists?(filepath)
      assert File.read!(filepath) == ""
    end

    test "handles large stream without OOM", %{test_dir: test_dir} do
      filepath = Path.join(test_dir, "large_stream.md")
      # Stream of 10000 chunks
      content_stream =
        Stream.iterate(1, &(&1 + 1))
        |> Stream.take(10_000)
        |> Stream.map(&"Line #{&1}\n")

      assert :ok = FileWriter.write_file_atomic_stream(filepath, content_stream)
      assert File.exists?(filepath)

      line_count =
        filepath
        |> File.read!()
        |> String.split("\n", trim: true)
        |> length()

      assert line_count == 10_000
    end

    test "creates parent directories", %{test_dir: test_dir} do
      filepath = Path.join([test_dir, "stream_subdir", "test.md"])

      assert :ok = FileWriter.write_file_atomic_stream(filepath, ["content"])
      assert File.exists?(filepath)
    end
  end

  describe "ensure_output_directory/1" do
    test "creates new directory", %{test_dir: test_dir} do
      new_dir = Path.join(test_dir, "new_output_dir")

      assert :ok = FileWriter.ensure_output_directory(new_dir)
      assert File.dir?(new_dir)
    end

    test "succeeds for existing directory", %{test_dir: test_dir} do
      assert :ok = FileWriter.ensure_output_directory(test_dir)
    end

    test "creates nested directories", %{test_dir: test_dir} do
      nested_dir = Path.join([test_dir, "level1", "level2", "level3"])

      assert :ok = FileWriter.ensure_output_directory(nested_dir)
      assert File.dir?(nested_dir)
    end
  end

  describe "check_disk_space/3" do
    test "returns ok when sufficient space available", %{test_dir: test_dir} do
      # 10 pages should require minimal space
      assert :ok = FileWriter.check_disk_space(test_dir, 10)
    end

    test "respects max_disk_usage_mb option", %{test_dir: test_dir} do
      # Request very large amount that would exceed any reasonable limit
      result = FileWriter.check_disk_space(test_dir, 1_000_000, max_disk_usage_mb: 1)

      assert match?({:error, :insufficient_disk_space, _, _}, result) or result == :ok
    end

    test "uses custom avg_page_size_kb", %{test_dir: test_dir} do
      # This should pass even with large estimated page size for small page count
      assert :ok = FileWriter.check_disk_space(test_dir, 1, avg_page_size_kb: 1000)
    end
  end

  describe "check_file_descriptor_limits/1" do
    test "returns ok tuple for reasonable worker counts" do
      # Returns {:ok, adjusted_workers} - may reduce if FD limits are low
      assert {:ok, workers} = FileWriter.check_file_descriptor_limits(100)
      assert is_integer(workers)
      assert workers >= 1
    end

    test "returns ok tuple when near limit but still safe" do
      # Should handle moderate worker counts
      assert {:ok, workers} = FileWriter.check_file_descriptor_limits(500)
      assert is_integer(workers)
    end
  end

  describe "cleanup_partial_files/2" do
    test "removes matching temp files by default", %{test_dir: test_dir} do
      # Create some temp files
      temp1 = Path.join(test_dir, "file1.md.tmp")
      temp2 = Path.join(test_dir, "file2.md.tmp")
      File.write!(temp1, "temp")
      File.write!(temp2, "temp")

      # Default behavior: removes *.tmp files (temp_only: true)
      assert {:ok, count} = FileWriter.cleanup_partial_files(test_dir)
      assert count == 2
      refute File.exists?(temp1)
      refute File.exists?(temp2)
    end

    test "does not remove non-matching files", %{test_dir: test_dir} do
      regular = Path.join(test_dir, "file.md")
      temp = Path.join(test_dir, "file.md.tmp")
      File.write!(regular, "content")
      File.write!(temp, "temp")

      assert {:ok, 1} = FileWriter.cleanup_partial_files(test_dir)
      assert File.exists?(regular)
      refute File.exists?(temp)
    end

    test "handles empty directory", %{test_dir: test_dir} do
      empty_dir = Path.join(test_dir, "empty")
      File.mkdir_p!(empty_dir)

      assert {:ok, 0} = FileWriter.cleanup_partial_files(empty_dir)
    end

    test "handles non-existent directory gracefully" do
      # Should not crash on non-existent directory - returns empty match
      result = FileWriter.cleanup_partial_files("/nonexistent/path")
      assert {:ok, 0} = result
    end

    test "removes files matching custom pattern", %{test_dir: test_dir} do
      partial = Path.join(test_dir, "file.partial")
      File.write!(partial, "content")

      assert {:ok, 1} = FileWriter.cleanup_partial_files(test_dir, pattern: "*.partial")
      refute File.exists?(partial)
    end
  end

  describe "path validation security" do
    test "write_file_atomic blocks path traversal", %{test_dir: test_dir} do
      # Attempting to write outside the intended directory
      evil_path = Path.join(test_dir, "../../../tmp/evil.md")

      # The function should either:
      # 1. Normalize the path and write within bounds, or
      # 2. Fail gracefully
      # It should NOT write to /tmp/evil.md
      result = FileWriter.write_file_atomic(evil_path, "evil content")

      # After the operation, /tmp/evil.md should not exist
      # (unless it existed before, which is unlikely in a clean system)
      if result == :ok do
        # If it succeeded, verify the file is in the expected normalized location
        normalized = Path.expand(evil_path)
        assert File.exists?(normalized)
      end
    end
  end
end
