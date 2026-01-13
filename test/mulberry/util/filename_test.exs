defmodule Mulberry.Util.FilenameTest do
  @moduledoc """
  Tests for the Filename utility module focusing on security-critical functions.
  """

  use ExUnit.Case, async: true

  alias Mulberry.Util.Filename

  describe "validate_no_path_traversal/2" do
    test "blocks simple path traversal with ../" do
      assert {:error, :path_traversal_attempt} =
               Filename.validate_no_path_traversal("/tmp/output/../etc/passwd", "/tmp/output")
    end

    test "blocks nested path traversal" do
      assert {:error, :path_traversal_attempt} =
               Filename.validate_no_path_traversal(
                 "/tmp/output/foo/../../etc/passwd",
                 "/tmp/output"
               )
    end

    test "blocks absolute paths outside directory" do
      assert {:error, :path_traversal_attempt} =
               Filename.validate_no_path_traversal("/etc/passwd", "/tmp/output")
    end

    test "blocks traversal at start of path" do
      assert {:error, :path_traversal_attempt} =
               Filename.validate_no_path_traversal("../etc/passwd", "/tmp/output")
    end

    test "allows safe paths within directory" do
      assert :ok = Filename.validate_no_path_traversal("/tmp/output/file.md", "/tmp/output")
    end

    test "allows safe paths in subdirectory" do
      assert :ok =
               Filename.validate_no_path_traversal("/tmp/output/subdir/file.md", "/tmp/output")
    end

    test "allows output directory itself" do
      assert :ok = Filename.validate_no_path_traversal("/tmp/output", "/tmp/output")
    end

    test "handles trailing slashes in output_dir" do
      assert :ok = Filename.validate_no_path_traversal("/tmp/output/file.md", "/tmp/output/")
    end

    test "blocks similar named directories (output-evil)" do
      assert {:error, :path_traversal_attempt} =
               Filename.validate_no_path_traversal("/tmp/output-evil/file.md", "/tmp/output")
    end
  end

  describe "sanitize/1" do
    test "removes dangerous characters" do
      # Slashes, colons, etc. are removed by the regex
      assert {:ok, "filename"} = Filename.sanitize("file/name")
      assert {:ok, "filename"} = Filename.sanitize("file\\name")
      assert {:ok, "filename"} = Filename.sanitize("file:name")
    end

    test "removes null bytes" do
      assert {:ok, "filename"} = Filename.sanitize("file\x00name")
    end

    test "handles path traversal attempts" do
      # Dots and slashes are removed, leaving just the words
      assert {:ok, "etcpasswd"} = Filename.sanitize("../etc/passwd")
      assert {:ok, "etcpasswd"} = Filename.sanitize("..\\etc\\passwd")
    end

    test "converts to lowercase and replaces underscores with hyphens" do
      # sanitize: lowercase, replace spaces/underscores with hyphens, remove other chars
      # "my-file_name.md" -> lowercase -> "my-file_name.md" -> remove dots -> "my-file_namemd"
      # -> replace underscore with hyphen -> "my-file-namemd"
      assert {:ok, "my-file-namemd"} = Filename.sanitize("my-file_name.md")
    end

    test "preserves unicode letters" do
      assert {:ok, result} = Filename.sanitize("file-café.md")
      assert result =~ "file"
      assert result =~ "café"
    end

    test "handles empty string" do
      assert {:error, :empty_after_sanitization} = Filename.sanitize("")
    end

    test "handles string that becomes empty after sanitization" do
      assert {:error, :empty_after_sanitization} = Filename.sanitize("///")
    end

    test "removes command injection attempts" do
      # Semicolons, backticks, $, parens are removed
      # Spaces become hyphens, multiple hyphens collapsed
      assert {:ok, "file-rm-rf"} = Filename.sanitize("file; rm -rf /")
      assert {:ok, "filewhoami"} = Filename.sanitize("file`whoami`")
      # "file$(cat /etc/passwd)" -> remove $()/ -> "filecat etcpasswd" -> space->hyphen
      assert {:ok, "filecat-etcpasswd"} = Filename.sanitize("file$(cat /etc/passwd)")
    end

    test "removes pipe characters" do
      assert {:ok, "filename"} = Filename.sanitize("file|name")
    end
  end

  describe "check_reserved_filename/1" do
    test "prefixes Windows reserved names" do
      assert {:ok, "_con.md"} = Filename.check_reserved_filename("con.md")
      assert {:ok, "_prn.md"} = Filename.check_reserved_filename("prn.md")
      assert {:ok, "_aux.md"} = Filename.check_reserved_filename("aux.md")
      assert {:ok, "_nul.md"} = Filename.check_reserved_filename("nul.md")
    end

    test "handles case-insensitive reserved names" do
      assert {:ok, "_CON.md"} = Filename.check_reserved_filename("CON.md")
      assert {:ok, "_Con.md"} = Filename.check_reserved_filename("Con.md")
    end

    test "prefixes COM and LPT ports" do
      assert {:ok, "_com1.md"} = Filename.check_reserved_filename("com1.md")
      assert {:ok, "_lpt1.md"} = Filename.check_reserved_filename("lpt1.md")
      assert {:ok, "_com9.md"} = Filename.check_reserved_filename("com9.md")
    end

    test "allows normal filenames" do
      assert {:ok, "normal.md"} = Filename.check_reserved_filename("normal.md")
      assert {:ok, "myfile.md"} = Filename.check_reserved_filename("myfile.md")
    end

    test "allows filenames containing reserved words" do
      assert {:ok, "configure.md"} = Filename.check_reserved_filename("configure.md")
      assert {:ok, "aux-file.md"} = Filename.check_reserved_filename("aux-file.md")
    end

    test "prefixes hyphen-prefixed filenames" do
      assert {:ok, "_-flag.md"} = Filename.check_reserved_filename("-flag.md")
      assert {:ok, "_--help"} = Filename.check_reserved_filename("--help")
    end

    test "prefixes hidden files (dot-prefixed)" do
      assert {:ok, "_.hidden"} = Filename.check_reserved_filename(".hidden")
      assert {:ok, "_.gitignore"} = Filename.check_reserved_filename(".gitignore")
    end

    test "prefixes current and parent directory" do
      assert {:ok, "_."} = Filename.check_reserved_filename(".")
      assert {:ok, "_.."} = Filename.check_reserved_filename("..")
    end
  end

  describe "from_url/2" do
    test "generates filename from URL" do
      assert {:ok, filename} = Filename.from_url("https://example.com/page", [])
      assert String.ends_with?(filename, ".md")
      assert String.contains?(filename, "example")
    end

    test "handles URLs with query strings" do
      assert {:ok, filename} = Filename.from_url("https://example.com/page?foo=bar", [])
      assert String.ends_with?(filename, ".md")
    end

    test "handles URLs with special characters" do
      assert {:ok, filename} = Filename.from_url("https://example.com/path/to/file", [])
      assert String.ends_with?(filename, ".md")
      refute String.contains?(filename, "/")
    end

    test "validates against path traversal with output_dir" do
      assert {:ok, filename} =
               Filename.from_url("https://example.com/../etc", output_dir: "/tmp/output")

      assert String.ends_with?(filename, ".md")
      refute String.contains?(filename, "..")
    end
  end

  describe "from_title/2" do
    test "generates filename from title" do
      assert {:ok, "my-page-title.md"} = Filename.from_title("My Page Title", [])
    end

    test "handles empty title with fallback URL" do
      assert {:ok, filename} =
               Filename.from_title("", fallback_url: "https://example.com/page")

      assert String.ends_with?(filename, ".md")
    end

    test "handles special characters in title" do
      assert {:ok, filename} = Filename.from_title("Title: With \"Special\" Chars!", [])
      assert String.ends_with?(filename, ".md")
      refute String.contains?(filename, ":")
      refute String.contains?(filename, "\"")
    end

    test "limits filename length" do
      long_title = String.duplicate("a", 500)
      assert {:ok, filename} = Filename.from_title(long_title, [])
      assert byte_size(filename) <= 255
    end
  end

  describe "from_hash/2" do
    test "generates deterministic filename from content" do
      assert {:ok, filename1} = Filename.from_hash("https://example.com", [])
      assert {:ok, filename2} = Filename.from_hash("https://example.com", [])
      assert filename1 == filename2
    end

    test "generates different filenames for different content" do
      assert {:ok, filename1} = Filename.from_hash("content1", [])
      assert {:ok, filename2} = Filename.from_hash("content2", [])
      assert filename1 != filename2
    end

    test "generates safe filenames" do
      assert {:ok, filename} = Filename.from_hash("https://evil.com/../etc/passwd", [])
      assert String.ends_with?(filename, ".md")
      refute String.contains?(filename, "..")
      refute String.contains?(filename, "/")
    end
  end

  describe "handle_existing_file/2" do
    setup do
      # Create a temp directory for testing
      temp_dir = System.tmp_dir!()
      test_dir = Path.join(temp_dir, "filename_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(test_dir)
      on_exit(fn -> File.rm_rf!(test_dir) end)
      {:ok, test_dir: test_dir}
    end

    test "returns write for non-existing file", %{test_dir: test_dir} do
      filepath = Path.join(test_dir, "new_file.md")
      assert {:ok, :write, ^filepath} = Filename.handle_existing_file(filepath, :skip)
    end

    test "returns skip for existing file with skip policy", %{test_dir: test_dir} do
      filepath = Path.join(test_dir, "existing.md")
      File.write!(filepath, "content")

      assert {:ok, :skip} = Filename.handle_existing_file(filepath, :skip)
    end

    test "returns write for existing file with overwrite policy", %{test_dir: test_dir} do
      filepath = Path.join(test_dir, "existing.md")
      File.write!(filepath, "content")

      assert {:ok, :write, ^filepath} = Filename.handle_existing_file(filepath, :overwrite)
    end

    test "returns error for existing file with error policy", %{test_dir: test_dir} do
      filepath = Path.join(test_dir, "existing.md")
      File.write!(filepath, "content")

      assert {:error, :file_exists, ^filepath} =
               Filename.handle_existing_file(filepath, :error)
    end

    test "returns incremented path for existing file with increment policy", %{test_dir: test_dir} do
      filepath = Path.join(test_dir, "existing.md")
      File.write!(filepath, "content")

      assert {:ok, :write, new_path} = Filename.handle_existing_file(filepath, :increment)
      assert new_path != filepath
      # Uses zero-padded format: existing-0001.md
      assert String.contains?(new_path, "existing-0001.md")
    end
  end

  describe "ensure_unique/2" do
    setup do
      temp_dir = System.tmp_dir!()
      test_dir = Path.join(temp_dir, "unique_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(test_dir)
      on_exit(fn -> File.rm_rf!(test_dir) end)
      {:ok, test_dir: test_dir}
    end

    test "returns original filename if no collision", %{test_dir: test_dir} do
      assert {:ok, "file.md"} = Filename.ensure_unique(test_dir, "file.md")
    end

    test "increments filename on collision", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "file.md"), "content")

      assert {:ok, unique_name} = Filename.ensure_unique(test_dir, "file.md")
      assert unique_name != "file.md"
      assert String.starts_with?(unique_name, "file")
    end

    test "handles multiple collisions", %{test_dir: test_dir} do
      # Uses zero-padded format: file-0001.md, file-0002.md, etc.
      File.write!(Path.join(test_dir, "file.md"), "content")
      File.write!(Path.join(test_dir, "file-0001.md"), "content")
      File.write!(Path.join(test_dir, "file-0002.md"), "content")

      assert {:ok, unique_name} = Filename.ensure_unique(test_dir, "file.md")
      refute File.exists?(Path.join(test_dir, unique_name))
      assert unique_name == "file-0003.md"
    end
  end

  describe "ensure_length/2" do
    test "returns filename unchanged if under limit" do
      assert "short.md" = Filename.ensure_length("short.md", 255)
    end

    test "truncates long filenames" do
      # ensure_length just truncates the raw string, doesn't preserve extension
      # This is used for base names before extension is added
      long_name = String.duplicate("a", 300)
      result = Filename.ensure_length(long_name, 100)
      assert byte_size(result) <= 100
    end

    test "truncates at word boundary when possible" do
      # With hyphens, it tries to break at word boundary
      long_name = "this-is-a-very-long-filename-with-many-parts"
      result = Filename.ensure_length(long_name, 25)
      assert byte_size(result) <= 25
      # Should break at a hyphen
      refute String.ends_with?(result, "-")
    end
  end
end
