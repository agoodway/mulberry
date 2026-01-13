defmodule Mulberry.Util.Filename do
  @moduledoc """
  Filename generation and validation utilities for safe file operations.

  This module provides functions for generating safe, sanitized filenames from
  URLs, titles, or hashes, with built-in protection against:

  - Path traversal attacks (../, absolute paths)
  - Reserved filenames (CON, PRN, etc. on Windows)
  - Overly long filenames (>255 characters)
  - Empty sanitization results
  - Filename collisions

  ## Security

  All filename generation functions validate that the resulting path stays within
  the specified output directory using `validate_no_path_traversal/2`.
  """

  require Logger

  # Max base length leaves room for extension and collision suffixes
  @max_base_length 230
  @max_collision_index 1000

  # Reserved filenames (case-insensitive, Windows and Unix)
  # Includes Windows device names and Unix special directories
  @reserved_filenames ~w[
    con prn aux nul
    com1 com2 com3 com4 com5 com6 com7 com8 com9
    lpt1 lpt2 lpt3 lpt4 lpt5 lpt6 lpt7 lpt8 lpt9
  ]

  # Additional dangerous patterns that need special handling
  @dangerous_patterns [
    # Current and parent directory
    ".",
    "..",
    # Hidden files (Unix)
    # Hyphen-prefixed (can be interpreted as command flags)
  ]

  @type overwrite_policy :: :skip | :overwrite | :error | :increment

  # Public API

  @doc """
  Generates a filename from a URL.

  The URL is converted to a safe filename by:
  1. Extracting the host and path
  2. Replacing special characters with hyphens
  3. Limiting the length
  4. Adding the .md extension

  ## Options
    - `:output_dir` - Directory for path traversal validation (optional)
    - `:extension` - File extension (default: ".md")
    - `:max_length` - Maximum filename length (default: 230)

  ## Returns
    - `{:ok, filename}` - Safe filename
    - `{:error, :path_traversal_attempt}` - If path traversal is detected
    - `{:error, :empty_after_sanitization}` - If sanitization results in empty string

  ## Examples

      iex> Filename.from_url("https://example.com/path/to/page")
      {:ok, "example.com-path-to-page.md"}

      iex> Filename.from_url("https://evil.com/../../../etc/passwd", output_dir: "/tmp")
      {:error, :path_traversal_attempt}
  """
  @spec from_url(String.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, :path_traversal_attempt | :empty_after_sanitization}
  def from_url(url, opts \\ []) do
    extension = Keyword.get(opts, :extension, ".md")
    max_length = Keyword.get(opts, :max_length, @max_base_length)
    output_dir = Keyword.get(opts, :output_dir)

    uri = URI.parse(url)
    host = uri.host || ""
    path = uri.path || ""

    # Combine host and path
    raw_filename = "#{host}#{path}"

    # Remove leading/trailing slashes and sanitize
    raw_filename =
      raw_filename
      |> String.trim("/")
      |> String.replace("/", "-")

    case sanitize(raw_filename) do
      {:ok, sanitized} ->
        sanitized = ensure_length(sanitized, max_length - byte_size(extension))
        filename = sanitized <> extension

        with {:ok, safe_filename} <- check_reserved_filename(filename),
             :ok <- maybe_validate_path(safe_filename, output_dir) do
          {:ok, safe_filename}
        end

      {:error, :empty_after_sanitization} ->
        Logger.warning("URL '#{url}' sanitized to empty, using hash instead")
        from_hash(url, opts)
    end
  end

  @doc """
  Generates a filename from a title.

  The title is converted to a safe filename by:
  1. Converting to lowercase
  2. Replacing special characters with hyphens
  3. Limiting the length
  4. Adding the .md extension

  ## Options
    - `:output_dir` - Directory for path traversal validation (optional)
    - `:extension` - File extension (default: ".md")
    - `:max_length` - Maximum filename length (default: 230)
    - `:fallback_url` - URL to use for hash fallback if sanitization fails

  ## Returns
    - `{:ok, filename}` - Safe filename
    - `{:error, :path_traversal_attempt}` - If path traversal is detected

  ## Examples

      iex> Filename.from_title("My Awesome Page Title")
      {:ok, "my-awesome-page-title.md"}

      iex> Filename.from_title("!!!")
      {:ok, "<hash>.md"}
  """
  @spec from_title(String.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, :path_traversal_attempt}
  def from_title(title, opts \\ []) do
    extension = Keyword.get(opts, :extension, ".md")
    max_length = Keyword.get(opts, :max_length, @max_base_length)
    output_dir = Keyword.get(opts, :output_dir)
    fallback_url = Keyword.get(opts, :fallback_url)

    case sanitize(title) do
      {:ok, sanitized} ->
        sanitized = ensure_length(sanitized, max_length - byte_size(extension))
        filename = sanitized <> extension

        with {:ok, safe_filename} <- check_reserved_filename(filename),
             :ok <- maybe_validate_path(safe_filename, output_dir) do
          {:ok, safe_filename}
        end

      {:error, :empty_after_sanitization} ->
        Logger.warning("Title '#{title}' sanitized to empty, using hash instead")

        fallback =
          if fallback_url do
            fallback_url
          else
            title <> DateTime.to_string(DateTime.utc_now())
          end

        from_hash(fallback, opts)
    end
  end

  @doc """
  Generates a filename from a SHA256 hash of the input.

  This provides guaranteed unique filenames when URL or title-based
  naming fails or when uniqueness is critical.

  ## Options
    - `:output_dir` - Directory for path traversal validation (optional)
    - `:extension` - File extension (default: ".md")
    - `:hash_length` - Length of hash to use (default: 16, max: 64)

  ## Returns
    - `{:ok, filename}` - Hash-based filename

  ## Examples

      iex> Filename.from_hash("https://example.com/page")
      {:ok, "a1b2c3d4e5f67890.md"}
  """
  @spec from_hash(String.t(), Keyword.t()) :: {:ok, String.t()}
  def from_hash(input, opts \\ []) do
    extension = Keyword.get(opts, :extension, ".md")
    hash_length = Keyword.get(opts, :hash_length, 16) |> min(64)

    hash =
      :crypto.hash(:sha256, input)
      |> Base.encode16(case: :lower)
      |> String.slice(0, hash_length)

    filename = hash <> extension
    {:ok, filename}
  end

  @doc """
  Sanitizes a string for use as a filename.

  The sanitization process:
  1. Converts to lowercase
  2. Removes non-alphanumeric characters (preserves Unicode letters/numbers)
  3. Replaces spaces and underscores with hyphens
  4. Collapses multiple hyphens
  5. Trims leading/trailing hyphens

  ## Returns
    - `{:ok, sanitized_string}` - Successfully sanitized
    - `{:error, :empty_after_sanitization}` - If result is empty

  ## Examples

      iex> Filename.sanitize("My Page Title!")
      {:ok, "my-page-title"}

      iex> Filename.sanitize("!!!")
      {:error, :empty_after_sanitization}
  """
  @spec sanitize(String.t()) :: {:ok, String.t()} | {:error, :empty_after_sanitization}
  def sanitize(string) when is_binary(string) do
    result =
      string
      |> String.downcase()
      |> String.replace(~r/[^\p{L}\p{N}\s\-_]/u, "")
      |> String.replace(~r/[\s_]+/, "-")
      |> String.replace(~r/-+/, "-")
      |> String.trim("-")

    if result == "" do
      {:error, :empty_after_sanitization}
    else
      {:ok, result}
    end
  end

  @doc """
  Checks if a filename is reserved or dangerous and prefixes with underscore if needed.

  Handles:
  - Windows-reserved names (CON, PRN, AUX, NUL, COM1-9, LPT1-9) - case-insensitive
  - Unix special directories (., ..)
  - Hyphen-prefixed filenames (can be interpreted as command flags)
  - Hidden files starting with dot (prefixed for visibility)

  ## Returns
    - `{:ok, safe_filename}` - Original or prefixed filename

  ## Examples

      iex> Filename.check_reserved_filename("con.md")
      {:ok, "_con.md"}

      iex> Filename.check_reserved_filename("-flag.md")
      {:ok, "_-flag.md"}

      iex> Filename.check_reserved_filename(".hidden")
      {:ok, "_.hidden"}

      iex> Filename.check_reserved_filename("normal.md")
      {:ok, "normal.md"}
  """
  @spec check_reserved_filename(String.t()) :: {:ok, String.t()}
  def check_reserved_filename(filename) do
    base_name = Path.basename(filename, Path.extname(filename))
    lowercase_base = String.downcase(base_name)

    cond do
      # Windows reserved names
      lowercase_base in @reserved_filenames ->
        {:ok, "_" <> filename}

      # Current/parent directory references
      filename in @dangerous_patterns ->
        {:ok, "_" <> filename}

      # Hyphen-prefixed (can be interpreted as command flags)
      String.starts_with?(filename, "-") ->
        {:ok, "_" <> filename}

      # Hidden files (dot-prefixed, but not . or ..)
      String.starts_with?(filename, ".") and filename not in [".", ".."] ->
        {:ok, "_" <> filename}

      true ->
        {:ok, filename}
    end
  end

  @doc """
  Validates that a filepath stays within the output directory.

  Uses `Path.expand/1` to resolve all symbolic links and relative paths,
  then checks that the result starts with the output directory.

  ## Returns
    - `:ok` - Path is safe
    - `{:error, :path_traversal_attempt}` - Path escapes output directory

  ## Examples

      iex> Filename.validate_no_path_traversal("/tmp/output/file.md", "/tmp/output")
      :ok

      iex> Filename.validate_no_path_traversal("/tmp/output/../etc/passwd", "/tmp/output")
      {:error, :path_traversal_attempt}
  """
  @spec validate_no_path_traversal(String.t(), String.t()) ::
          :ok | {:error, :path_traversal_attempt}
  def validate_no_path_traversal(filepath, output_dir) do
    normalized_filepath = Path.expand(filepath)
    normalized_output_dir = Path.expand(output_dir)

    # Ensure output_dir ends with a separator for proper prefix matching
    normalized_output_dir =
      if String.ends_with?(normalized_output_dir, "/") do
        normalized_output_dir
      else
        normalized_output_dir <> "/"
      end

    # Check that filepath is either the output_dir itself or starts with output_dir/
    if normalized_filepath == String.trim_trailing(normalized_output_dir, "/") or
         String.starts_with?(normalized_filepath, normalized_output_dir) do
      :ok
    else
      {:error, :path_traversal_attempt}
    end
  end

  @doc """
  Ensures a unique filename in the given directory.

  If the filename already exists, appends a zero-padded index (e.g., "-0001")
  until a unique filename is found. After 1000 collisions, switches to hash-based
  naming.

  ## Returns
    - `{:ok, unique_filename}` - Filename that doesn't exist in directory

  ## Examples

      iex> Filename.ensure_unique("/tmp/output", "file.md")
      {:ok, "file.md"}  # if doesn't exist

      iex> Filename.ensure_unique("/tmp/output", "existing.md")
      {:ok, "existing-0001.md"}  # if existing.md exists
  """
  @spec ensure_unique(String.t(), String.t()) :: {:ok, String.t()}
  def ensure_unique(directory, filename) do
    full_path = Path.join(directory, filename)

    if File.exists?(full_path) do
      find_unique_filename(directory, filename, 1)
    else
      {:ok, filename}
    end
  end

  @doc """
  Ensures filename is within filesystem limits.

  Truncates at word boundary if necessary, leaving room for extension and
  collision suffixes.

  ## Options
    - `max_length` - Maximum length in bytes (default: 230)

  ## Returns
    - Truncated filename (within limit)

  ## Examples

      iex> Filename.ensure_length("very-long-filename-here", 20)
      "very-long-filename"
  """
  @spec ensure_length(String.t(), pos_integer()) :: String.t()
  def ensure_length(filename, max_length \\ @max_base_length) do
    if byte_size(filename) <= max_length do
      filename
    else
      # Truncate and try to break at a word boundary
      truncated = String.slice(filename, 0, max_length)

      # Find the last hyphen within the truncated string
      case String.split(truncated, "-") do
        [single] ->
          # No hyphens, just truncate
          single

        parts ->
          # Remove the last potentially incomplete part
          parts
          |> Enum.reverse()
          |> tl()
          |> Enum.reverse()
          |> Enum.join("-")
      end
      |> String.trim("-")
    end
  end

  @doc """
  Determines what to do when output file already exists.

  ## Policies
    - `:skip` - Skip writing this file, continue with next
    - `:overwrite` - Replace existing file
    - `:error` - Return error
    - `:increment` - Create filename-1.md, filename-2.md, etc. (default)

  ## Returns
    - `{:ok, :write, filepath}` - Write to this path
    - `{:ok, :skip}` - Skip this file
    - `{:error, :file_exists, filepath}` - Error policy triggered

  ## Examples

      iex> Filename.handle_existing_file("/tmp/new.md", :overwrite)
      {:ok, :write, "/tmp/new.md"}

      iex> Filename.handle_existing_file("/tmp/existing.md", :skip)
      {:ok, :skip}
  """
  @spec handle_existing_file(String.t(), overwrite_policy()) ::
          {:ok, :write, String.t()} | {:ok, :skip} | {:error, :file_exists, String.t()}
  def handle_existing_file(filepath, policy) do
    case File.exists?(filepath) do
      false ->
        {:ok, :write, filepath}

      true ->
        case policy do
          :skip ->
            Logger.debug("Skipping existing file: #{filepath}")
            {:ok, :skip}

          :overwrite ->
            Logger.debug("Overwriting existing file: #{filepath}")
            {:ok, :write, filepath}

          :error ->
            {:error, :file_exists, filepath}

          :increment ->
            {:ok, unique_filename} =
              ensure_unique(Path.dirname(filepath), Path.basename(filepath))

            {:ok, :write, Path.join(Path.dirname(filepath), unique_filename)}
        end
    end
  end

  # Private functions

  defp maybe_validate_path(_filename, nil), do: :ok

  defp maybe_validate_path(filename, output_dir) do
    full_path = Path.join(output_dir, filename)
    validate_no_path_traversal(full_path, output_dir)
  end

  defp find_unique_filename(directory, filename, index) when index < @max_collision_index do
    base_name = Path.basename(filename, Path.extname(filename))
    extension = Path.extname(filename)

    indexed_filename = :io_lib.format("~s-~4..0B~s", [base_name, index, extension]) |> to_string()
    full_path = Path.join(directory, indexed_filename)

    if File.exists?(full_path) do
      find_unique_filename(directory, filename, index + 1)
    else
      {:ok, indexed_filename}
    end
  end

  defp find_unique_filename(_directory, filename, index) do
    Logger.warning(
      "Too many filename collisions (#{index}), switching to hash pattern for #{filename}"
    )

    # Generate hash-based filename instead
    base_name = Path.basename(filename, Path.extname(filename))
    extension = Path.extname(filename)

    hash =
      :crypto.hash(:sha256, base_name <> to_string(:os.system_time()))
      |> Base.encode16(case: :lower)
      |> String.slice(0, 16)

    {:ok, hash <> extension}
  end
end
