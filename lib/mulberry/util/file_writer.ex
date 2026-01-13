defmodule Mulberry.Util.FileWriter do
  @moduledoc """
  Atomic file writing operations with resource management.

  This module provides safe file writing operations that:

  - Use atomic writes (temp file + rename) to prevent corruption
  - Check available disk space before writes
  - Monitor file descriptor limits
  - Handle interrupts gracefully
  - Support streaming for large files

  ## Atomic Writes

  All write operations use a temporary file strategy:
  1. Write content to a `.tmp` file
  2. Verify the write succeeded
  3. Rename to the final filename (atomic on most filesystems)
  4. Clean up temp file on failure

  ## Resource Management

  Before starting large operations, use `check_disk_space/3` and
  `check_file_descriptor_limits/1` to ensure adequate resources.
  """

  require Logger

  @temp_extension ".tmp"
  @default_avg_page_size_kb 50
  @default_safety_multiplier 2.0
  @fd_per_worker 10

  # Public API

  @doc """
  Writes file atomically using temporary file strategy.

  The write process:
  1. Write to temp file (.tmp extension)
  2. Verify write succeeded
  3. Rename to final name (atomic on most filesystems)
  4. Clean up temp file if rename fails

  ## Returns
    - `:ok` - File written successfully
    - `{:error, reason}` - Write failed

  ## Examples

      iex> FileWriter.write_file_atomic("/tmp/output/file.md", "# Content")
      :ok
  """
  @spec write_file_atomic(String.t(), String.t()) :: :ok | {:error, any()}
  def write_file_atomic(filepath, content) do
    temp_path = filepath <> @temp_extension

    # Ensure directory exists
    dir = Path.dirname(filepath)

    case File.mkdir_p(dir) do
      :ok ->
        do_atomic_write(filepath, temp_path, content)

      {:error, reason} ->
        {:error, {:directory_creation_failed, reason}}
    end
  end

  @doc """
  Writes file atomically with streaming for large content.

  Similar to `write_file_atomic/2` but accepts a stream or enumerable
  for memory-efficient writing of large files.

  ## Returns
    - `:ok` - File written successfully
    - `{:error, reason}` - Write failed

  ## Examples

      iex> content_stream = Stream.iterate(1, &(&1 + 1)) |> Stream.take(1000)
      iex> FileWriter.write_file_atomic_stream("/tmp/output/large.md", content_stream)
      :ok
  """
  @spec write_file_atomic_stream(String.t(), Enumerable.t()) :: :ok | {:error, any()}
  def write_file_atomic_stream(filepath, content_stream) do
    temp_path = filepath <> @temp_extension
    dir = Path.dirname(filepath)

    case File.mkdir_p(dir) do
      :ok ->
        do_atomic_write_stream(filepath, temp_path, content_stream)

      {:error, reason} ->
        {:error, {:directory_creation_failed, reason}}
    end
  end

  @doc """
  Checks if sufficient disk space is available for crawl.

  Estimates required space based on page count and average markdown size.

  ## Options
    - `:avg_page_size_kb` - Average page size in KB (default: 50)
    - `:safety_multiplier` - Multiplier for safety buffer (default: 2.0)
    - `:max_disk_usage_mb` - Maximum disk usage allowed (default: no limit)

  ## Returns
    - `:ok` - Sufficient space available
    - `{:error, :insufficient_disk_space, required_mb, available_mb}` - Not enough space

  ## Examples

      iex> FileWriter.check_disk_space("/tmp/output", 100)
      :ok

      iex> FileWriter.check_disk_space("/tmp/output", 1000000, max_disk_usage_mb: 100)
      {:error, :insufficient_disk_space, 10000, 50000}
  """
  @spec check_disk_space(String.t(), pos_integer(), Keyword.t()) ::
          :ok | {:error, :insufficient_disk_space, pos_integer(), pos_integer()}
  def check_disk_space(output_dir, estimated_pages, opts \\ []) do
    available_mb = get_available_disk_space(output_dir)

    avg_page_size_kb = Keyword.get(opts, :avg_page_size_kb, @default_avg_page_size_kb)
    safety_multiplier = Keyword.get(opts, :safety_multiplier, @default_safety_multiplier)
    max_disk_usage_mb = Keyword.get(opts, :max_disk_usage_mb)

    required_mb = round(estimated_pages * avg_page_size_kb * safety_multiplier / 1024)

    # Check against both available space and max usage limit
    sufficient_space =
      cond do
        max_disk_usage_mb && required_mb > max_disk_usage_mb ->
          false

        available_mb < required_mb ->
          false

        true ->
          true
      end

    if sufficient_space do
      :ok
    else
      {:error, :insufficient_disk_space, required_mb, available_mb}
    end
  end

  @doc """
  Checks if system has sufficient file descriptors for crawl.

  Returns recommended max_workers value, potentially reduced from requested
  if file descriptor limits are too low.

  ## Returns
    - `{:ok, adjusted_workers}` - Safe number of workers
    - `{:error, :insufficient_file_descriptors}` - Even 1 worker not safe

  ## Examples

      iex> FileWriter.check_file_descriptor_limits(20)
      {:ok, 20}

      iex> FileWriter.check_file_descriptor_limits(100)
      {:ok, 50}  # Reduced due to FD limits
  """
  @spec check_file_descriptor_limits(pos_integer()) ::
          {:ok, pos_integer()} | {:error, :insufficient_file_descriptors}
  def check_file_descriptor_limits(requested_workers) do
    case get_fd_limits() do
      {:ok, soft_limit, _hard_limit} ->
        # Each worker needs: HTTP connection + file handle + overhead
        # Conservative estimate: 10 FD per worker, leave 50% headroom
        max_safe_workers = div(soft_limit, @fd_per_worker * 2)
        max_safe_workers = max(max_safe_workers, 1)

        if requested_workers > max_safe_workers do
          Logger.warning(
            "Requested #{requested_workers} workers exceeds safe limit of #{max_safe_workers}, " <>
              "reducing to #{max_safe_workers}"
          )

          {:ok, max_safe_workers}
        else
          {:ok, requested_workers}
        end

      {:error, _reason} ->
        # Can't determine limits, allow requested but log warning
        Logger.warning(
          "Could not determine file descriptor limits, using requested #{requested_workers} workers"
        )

        {:ok, requested_workers}
    end
  end

  @doc """
  Removes partial files from a directory.

  Useful for cleanup after interrupted operations. Removes files matching
  specific patterns that indicate incomplete writes.

  ## Options
    - `:temp_only` - Only remove .tmp files (default: true)
    - `:pattern` - Glob pattern for files to remove

  ## Returns
    - `{:ok, removed_count}` - Number of files removed

  ## Examples

      iex> FileWriter.cleanup_partial_files("/tmp/output")
      {:ok, 3}
  """
  @spec cleanup_partial_files(String.t(), Keyword.t()) :: {:ok, non_neg_integer()}
  def cleanup_partial_files(output_dir, opts \\ []) do
    temp_only = Keyword.get(opts, :temp_only, true)
    pattern = Keyword.get(opts, :pattern)

    files_to_remove =
      cond do
        pattern ->
          Path.wildcard(Path.join(output_dir, pattern))

        temp_only ->
          Path.wildcard(Path.join(output_dir, "*#{@temp_extension}"))

        true ->
          []
      end

    removed_count =
      files_to_remove
      |> Enum.map(fn file ->
        case File.rm(file) do
          :ok ->
            Logger.debug("Removed partial file: #{file}")
            1

          {:error, reason} ->
            Logger.warning("Failed to remove partial file #{file}: #{inspect(reason)}")
            0
        end
      end)
      |> Enum.sum()

    {:ok, removed_count}
  end

  @doc """
  Ensures the output directory exists and is writable.

  ## Returns
    - `:ok` - Directory exists and is writable
    - `{:error, :directory_creation_failed, reason}` - Cannot create directory
    - `{:error, :not_writable}` - Directory exists but is not writable

  ## Examples

      iex> FileWriter.ensure_output_directory("/tmp/output")
      :ok
  """
  @spec ensure_output_directory(String.t()) :: :ok | {:error, atom(), any()}
  def ensure_output_directory(output_dir) do
    case File.mkdir_p(output_dir) do
      :ok ->
        # Verify directory is writable by attempting to create a test file
        test_file = Path.join(output_dir, ".write_test_#{:rand.uniform(100_000)}")

        case File.write(test_file, "") do
          :ok ->
            File.rm(test_file)
            :ok

          {:error, reason} ->
            {:error, :not_writable, reason}
        end

      {:error, reason} ->
        {:error, :directory_creation_failed, reason}
    end
  end

  # Private functions

  defp do_atomic_write(filepath, temp_path, content) do
    with :ok <- File.write(temp_path, content),
         true <- File.exists?(temp_path),
         :ok <- File.rename(temp_path, filepath) do
      :ok
    else
      {:error, reason} ->
        # Clean up temp file on failure
        File.rm(temp_path)
        {:error, {:write_failed, reason}}

      false ->
        {:error, :temp_file_not_created}
    end
  end

  defp do_atomic_write_stream(filepath, temp_path, content_stream) do
    # Open temp file for streaming writes
    case File.open(temp_path, [:write, :utf8, :delayed_write]) do
      {:ok, file} ->
        try do
          # Write each chunk
          Enum.each(content_stream, fn chunk ->
            IO.write(file, chunk)
          end)

          File.close(file)

          # Verify and rename
          if File.exists?(temp_path) do
            case File.rename(temp_path, filepath) do
              :ok -> :ok
              {:error, reason} -> {:error, {:rename_failed, reason}}
            end
          else
            {:error, :temp_file_not_created}
          end
        rescue
          e ->
            File.close(file)
            File.rm(temp_path)
            {:error, {:stream_write_failed, e}}
        end

      {:error, reason} ->
        {:error, {:file_open_failed, reason}}
    end
  end

  defp get_available_disk_space(path) do
    # Validate and normalize the path first
    # System.cmd is safe from shell injection, but we should ensure valid paths
    normalized_path = Path.expand(path)

    # Only proceed if path exists or parent directory exists
    check_path =
      if File.exists?(normalized_path) do
        normalized_path
      else
        Path.dirname(normalized_path)
      end

    if File.exists?(check_path) do
      # Use df command to get available space in MB
      # Works on Linux and macOS
      case System.cmd("df", ["-m", check_path], stderr_to_stdout: true) do
        {output, 0} ->
          # Parse df output - available space is typically 4th column
          output
          |> String.split("\n")
          |> Enum.at(1, "")
          |> String.split(~r/\s+/)
          |> Enum.at(3, "0")
          |> String.to_integer()

        _ ->
          # Fallback: assume 10GB available if we can't determine
          Logger.warning("Could not determine available disk space, assuming 10GB")
          10_000
      end
    else
      Logger.warning("Path does not exist for disk space check: #{path}, assuming 10GB")
      10_000
    end
  rescue
    _ ->
      Logger.warning("Error determining disk space, assuming 10GB")
      10_000
  end

  defp get_fd_limits do
    # Try to get file descriptor limits
    # Works on Linux and macOS
    case System.cmd("ulimit", ["-n"], stderr_to_stdout: true) do
      {output, 0} ->
        limit =
          output
          |> String.trim()
          |> String.to_integer()

        {:ok, limit, limit}

      _ ->
        # Try reading from /proc on Linux
        case File.read("/proc/self/limits") do
          {:ok, content} ->
            parse_proc_limits(content)

          _ ->
            # Fallback: assume reasonable default
            {:ok, 1024, 1024}
        end
    end
  rescue
    _ ->
      {:ok, 1024, 1024}
  end

  defp parse_proc_limits(content) do
    # Parse /proc/self/limits for file descriptor limits
    content
    |> String.split("\n")
    |> Enum.find_value({:ok, 1024, 1024}, fn line ->
      if String.contains?(line, "Max open files") do
        parts = String.split(line, ~r/\s+/)

        soft =
          Enum.at(parts, 3, "1024")
          |> parse_limit_value()

        hard =
          Enum.at(parts, 4, "1024")
          |> parse_limit_value()

        {:ok, soft, hard}
      end
    end)
  end

  defp parse_limit_value("unlimited"), do: 1_000_000
  defp parse_limit_value(value), do: String.to_integer(value)
end
