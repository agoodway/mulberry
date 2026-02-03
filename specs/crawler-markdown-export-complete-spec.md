# Crawler Markdown Export - Complete Specification

**Document Version:** 2.0
**Date:** January 12, 2026
**Status:** Complete
**Author:** Technical Specification Team

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Overview](#2-overview)
3. [Functional Requirements](#3-functional-requirements)
4. [Security Requirements (CRITICAL)](#4-security-requirements-critical)
5. [Robustness Requirements](#5-robustness-requirements)
6. [Implementation Details](#6-implementation-details)
7. [Testing Requirements](#7-testing-requirements)
8. [API Reference](#8-api-reference)
9. [Usage Examples](#9-usage-examples)
10. [Error Handling](#10-error-handling)
11. [Performance Considerations](#11-performance-considerations)
12. [Acceptance Criteria](#12-acceptance-criteria)
13. [Quick Reference](#13-quick-reference)

---

## 1. Executive Summary

### 1.1 Purpose

Add markdown export functionality to Mulberry's crawler, enabling users to save crawled pages as individual markdown files or combined markdown documents. The implementation MUST prioritize security, robustness, and maintain backward compatibility.

### 1.2 Key Features

- **Individual Markdown Files:** Save each page as a separate `.md` file
- **Combined Markdown Document:** Optionally merge all pages into a single file with table of contents
- **Multiple Filename Patterns:** URL-based, title-based, or hash-based naming
- **Configurable Metadata:** Optional YAML frontmatter with crawl information
- **Security First:** Path traversal protection, atomic writes, input validation
- **Resource Awareness:** Disk space checking, file descriptor monitoring
- **Graceful Interrupts:** Clean shutdown with optional file cleanup

### 1.3 Non-Goals

- Markdown editing or transformation (beyond basic cleaning)
- Real-time markdown streaming during crawl
- Incremental updates or resume capability (as MVP)
- Other export formats (PDF, DOCX, etc.)

---

## 2. Overview

### 2.1 Background

The Mulberry package already has internal markdown support:
- HTML to markdown conversion via `Mulberry.HTML.to_markdown/1`
- WebPage documents store markdown in the `:markdown` field
- Single URL markdown export via `mix fetch_url --markdown --save`

However, the crawler (`mix crawl`) lacks markdown export capabilities and currently only supports console output and JSONL file output.

### 2.2 Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Mulberry.Crawler                      │
├─────────────────────────────────────────────────────────────┤
│                                                      │
│  ┌─────────────┐    ┌─────────────┐                │
│  │ URL Discovery│───▶│  Crawl Task │                │
│  └─────────────┘    └─────────────┘                │
│                              │                        │
│                              ▼                        │
│                    ┌──────────────────┐                 │
│                    │ Output Handler  │                 │
│                    └──────────────────┘                 │
│                              │                        │
│           ┌──────────────────┼──────────────────┐       │
│           │                  │                  │       │
│           ▼                  ▼                  ▼       │
│    ┌─────────┐      ┌──────────┐      ┌─────────┐   │
│    │ Console │      │  JSONL   │      │Markdown │   │
│    │ Output  │      │  Output  │      │ Output  │   │
│    └─────────┘      └──────────┘      └─────────┘   │
│                                              │         │
│                                              ▼         │
│                                   ┌──────────────────┐   │
│                                   │Filename Utility │   │
│                                   └──────────────────┘   │
│                                              │         │
│                                              ▼         │
│                                   ┌──────────────────┐   │
│                                   │  File System   │   │
│                                   │  (with checks) │   │
│                                   └──────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 2.3 Goals

- Add markdown export functionality to crawler
- Support both individual and combined markdown file output
- Maintain backward compatibility with existing output formats
- Follow Mulberry's protocol-based architecture
- Ensure proper file naming and directory management
- Prioritize security and robustness

---

## 3. Functional Requirements

### 3.1 Document Protocol Extension

#### Requirement 3.1.1: Add `to_markdown/2` to Document Protocol

**Priority:** High

Add a new protocol function to `Mulberry.Document`:

```elixir
@doc """
Converts the document to Markdown format.

## Options
  - `:clean_whitespace` - If true, removes excessive whitespace (default: false)
  - `:remove_empty_sections` - If true, removes empty sections (default: false)

## Definitions
  - "excessive whitespace": More than 2 consecutive newlines, lines with only whitespace,
    leading/trailing whitespace on each line
  - "empty sections": Heading with no non-whitespace content under it (< 50 chars),
    sections containing only structural elements

## Returns
  - `{:ok, String.t()}` - Markdown content
  - `{:error, reason}` - If conversion fails
"""
@spec to_markdown(t, Keyword.t()) :: {:ok, String.t()} | {:error, any()}
def to_markdown(value, opts \\ [])
```

**Implementation Requirements:**
- Must be implemented for all document types (WebPage, TextFile)
- Must handle cases where markdown is not available (return `{:error, :not_loaded}`)
- Must pass through options to implementation

### 3.2 WebPage Implementation

#### Requirement 3.2.1: Implement `to_markdown/2` for WebPage

**Priority:** High

```elixir
defimpl Mulberry.Document, for: Mulberry.Document.WebPage do
  def to_markdown(%WebPage{markdown: markdown} = web_page, opts)
      when is_binary(markdown) do
    cleaned_markdown =
      case Keyword.get(opts, :clean_whitespace, false) do
        true -> clean_whitespace(markdown)
        false -> markdown
      end

    final_markdown =
      case Keyword.get(opts, :remove_empty_sections, false) do
        true -> remove_empty_sections(cleaned_markdown)
        false -> cleaned_markdown
      end

    {:ok, final_markdown}
  end

  def to_markdown(%WebPage{}, _opts) do
    {:error, :not_loaded}
  end
end
```

**Implementation Requirements:**
- Return the stored markdown from the `:markdown` field
- Apply any cleaning options
- Return `{:error, :not_loaded}` if markdown is not available
- Preserve original markdown order and structure

### 3.3 Crawler Task Enhancement

#### Requirement 3.3.1: Add Markdown Output Format Option

**Priority:** High

Add `--format` option to `mix crawl` task:

```
--format <format>   Output format: console, jsonl, or markdown (default: console)
```

**Implementation Requirements:**
- Parse the format option in `parse_args/1`
- Validate format values (console, jsonl, markdown)
- Pass format to `handle_results/3` function
- Maintain backward compatibility (no format specified = console)

#### Requirement 3.3.2: Add Markdown-Specific Options

**Priority:** High

Add markdown-specific output options:

```
--output-dir <path>        Directory for markdown files (required for markdown format)
--filename-pattern <pattern>  Filename pattern: url, title, or hash (default: url)
--combined-filename <name>  Name for combined file (default: combined)
--combine-files            Combine all pages into single markdown file (default: false)
--add-metadata             Add crawl metadata to each file (default: true)
--no-metadata              Disable metadata addition
--overwrite                Overwrite existing files (default: increment)
--skip-existing            Skip crawling URLs that would overwrite files
--error-on-exists          Raise error if file would be overwritten
--cleanup-on-fail          Remove partially-written files on failure (default: false)
--resume                  Skip already-written files, continue crawl (default: false)
--progress                Show progress bar during file writes (default: false)
--max-disk-usage <mb>     Maximum disk usage in MB before stopping (default: no limit)
--avg-page-size <kb>     Average page size in KB for space estimation (default: 50)
--file-write-rate <n>     Maximum file writes per second (default: unlimited)
--validate-markdown        Check markdown syntax after generation (default: false)
```

**Implementation Requirements:**
- Parse markdown-specific options
- Validate that `--output-dir` is provided when format is markdown
- Default behavior: create individual files for each page
- When `--combine-files` is set, create a single combined markdown file

#### Requirement 3.3.3: Implement Markdown File Generation

**Priority:** High

Implement `handle_results/3` function to support markdown output:

```elixir
defp handle_results(results, format, output_opts)
```

**Flow:**
1. **Pre-flight Validation:**
   - Check output directory exists or can be created
   - Validate disk space (see Security Section 4.4)
   - Check file descriptor limits (see Section 5.2)
   - Validate all options

2. **For Individual Mode:**
   - For each result:
     - Load WebPage document with markdown
     - Generate filename based on pattern (with security validation)
     - Ensure filename is unique in directory
     - Write markdown file atomically
     - Handle existing files per overwrite policy
   - Log summary of files created

3. **For Combined Mode:**
   - Create single combined markdown file with:
     - Table of contents (optional, based on metadata option)
     - Section headers for each page
     - Page separators
   - Use streaming for large crawls
   - Write atomically

**Filename Generation Patterns:**
- `url`: Use URL path, sanitized: `https://example.com/path/page` → `example.com-path-page.md`
- `title`: Use page title, sanitized: `My Page Title` → `my-page-title.md`
- `hash`: Use SHA256 hash of URL (for guaranteed uniqueness): `abc123...md`

**Filename Sanitization:**
- Replace spaces with hyphens
- Remove special characters (except letters, numbers, hyphens, underscores)
- Limit to 255 characters total (including extension and suffix)
- Ensure filename is lowercase
- Handle reserved filenames (CON, PRN, etc.) by prefixing with "_"
- Fall back to hash if sanitization results in empty string

### 3.4 Markdown File Content

#### Requirement 3.4.1: Individual Markdown File Structure

**Priority:** High

Each individual markdown file should have the following structure when `--add-metadata` is true:

```markdown
---
url: https://example.com/page
title: Page Title
crawled_at: 2025-01-12T10:30:00Z
---

# Page Title

[Markdown content from page]
```

When `--no-metadata` is specified:
```markdown
# Page Title

[Markdown content from page]
```

**Implementation Requirements:**
- Use YAML frontmatter for metadata
- Only include metadata fields that have values
- Use ISO 8601 format for timestamps
- Ensure metadata separator (`---`) is present even if no metadata

#### Requirement 3.4.2: Combined Markdown File Structure

**Priority:** High

When `--combine-files` is enabled, create a single markdown file:

```markdown
# Crawl Results

**Source:** https://example.com
**Crawled:** 2025-01-12T10:30:00Z
**Pages:** 42

## Table of Contents

- [Page One](#page-one)
- [Page Two](#page-two)
...

---

## Page One

**URL:** https://example.com/page1
**Title:** Page One

[Markdown content from page1]

---

## Page Two

**URL:** https://example.com/page2
**Title:** Page Two

[Markdown content from page2]
```

**Implementation Requirements:**
- Generate table of contents with anchor links
- Use horizontal rules (`---`) between pages
- Include page metadata headers
- Skip TOC if `--no-metadata` is specified
- Ensure unique section headers (add index if needed: "Title", "Title-1", etc.)
- Use streaming for large files to avoid memory issues

---

## 4. Security Requirements (CRITICAL)

### 4.1 Path Traversal Protection (CRITICAL)

#### Requirement 4.1.1: Prevent Path Traversal Attacks

**Priority:** CRITICAL
**Security Impact:** HIGH

All filename generation functions MUST prevent path traversal attacks that could create files outside the intended output directory.

**Threat Model:**
- Malicious URLs containing `..` sequences
- URLs crafted to escape output directory
- Filenames with absolute paths
- Symbolic link attacks

**Implementation Requirements:**

```elixir
@doc """
Validates that a filepath stays within output directory.

Must use Path.expand() to resolve all symbolic links and relative paths.
Returns :ok if safe, {:error, :path_traversal_attempt} if unsafe.
"""
@spec validate_no_path_traversal(String.t(), String.t()) :: :ok | {:error, :path_traversal_attempt}
def validate_no_path_traversal(filepath, output_dir) do
  normalized_filepath = Path.expand(filepath)
  normalized_output_dir = Path.expand(output_dir)

  if String.starts_with?(normalized_filepath, normalized_output_dir) do
    :ok
  else
    {:error, :path_traversal_attempt}
  end
end
```

**Integration Points:**
- `Mulberry.Util.Filename.from_url/2` - MUST call validation before returning
- `Mulberry.Util.Filename.from_title/2` - MUST call validation before returning
- `Mulberry.Util.Filename.from_hash/2` - MUST call validation before returning
- All file write operations in crawler task - MUST use validated paths

**Test Cases:**
- [ ] URL with `../../etc/passwd.md` is rejected
- [ ] URL with `/absolute/path.md` is rejected
- [ ] URL with `\..\..\..` on Windows is rejected
- [ ] Normal URLs are accepted
- [ ] Output directory with symlinks is handled correctly
- [ ] Symbolic link attacks are prevented

### 4.2 Reserved Filename Handling

#### Requirement 4.2.1: Handle Reserved Filenames

**Priority:** HIGH
**Compatibility Impact:** HIGH

Filenames that are reserved by operating system MUST be handled to prevent errors.

**Implementation Requirements:**

```elixir
# Reserved filenames (case-insensitive, Windows and Unix)
@reserved_filenames ~w[
  con prn aux nul
  com1 com2 com3 com4 com5 com6 com7 com8 com9
  lpt1 lpt2 lpt3 lpt4 lpt5 lpt6 lpt7 lpt8 lpt9
  # Unix special
  . ..
]

@doc """
Checks if a filename is reserved and prepends underscore if needed.

Returns {:ok, safe_filename}.
"""
@spec check_reserved_filename(String.t()) :: {:ok, String.t()}
def check_reserved_filename(filename) do
  base_name = Path.basename(filename, Path.extname(filename))
  lowercase_base = String.downcase(base_name)

  if lowercase_base in @reserved_filenames do
    {:ok, "_" <> filename}
  else
    {:ok, filename}
  end
end
```

**Integration Points:**
- All filename generation functions
- `Mulberry.Util.Filename.ensure_unique/2`

**Test Cases:**
- [ ] `CON.md` becomes `_CON.md`
- [ ] `prn.md` becomes `_prn.md`
- [ ] `.md` becomes `_.md`
- [ ] `..md` becomes `_..md`
- [ ] Normal filenames are unchanged
- [ ] Works with different filename extensions
- [ ] Case-insensitive matching works

### 4.3 Empty Sanitization Result Handling

#### Requirement 4.3.1: Handle Empty Sanitization Results

**Priority:** HIGH
**User Experience Impact:** HIGH

When URL or title sanitization results in an empty string, MUST fall back to hash-based filename with a warning.

**Implementation Requirements:**

```elixir
@doc """
Sanitizes a string for use as a filename.

Returns {:ok, sanitized_string} or {:error, :empty_after_sanitization}.
"""
@spec sanitize(String.t()) :: {:ok, String.t()} | {:error, :empty_after_sanitization}
def sanitize(string) do
  result =
    string
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}\s\-_]/, "")
    |> String.replace(~r/[\s_]+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")

  if result == "" do
    {:error, :empty_after_sanitization}
  else
    {:ok, result}
  end
end

# Usage in filename generation
defp from_title_safe(title, url, opts) do
  case sanitize(title) do
    {:ok, sanitized} ->
      {:ok, sanitized <> ".md"}

    {:error, :empty_after_sanitization} ->
      Logger.warn("Title '#{title}' sanitized to empty, using hash instead")
      from_hash(url, opts)
  end
end
```

**Integration Points:**
- `Mulberry.Util.Filename.from_url/2`
- `Mulberry.Util.Filename.from_title/2`
- Any function that generates filenames from user input

**Test Cases:**
- [ ] Title of "!!!" falls back to hash
- [ ] Title of "   " falls back to hash
- [ ] Title of "???---___" falls back to hash
- [ ] Warning is logged when fallback occurs
- [ ] Hash-based filename is valid and unique
- [ ] Warning includes the problematic title

### 4.4 Disk Space Pre-Flight Check

#### Requirement 4.4.1: Check Available Disk Space

**Priority:** HIGH
**Data Integrity Impact:** HIGH

Before starting crawl, MUST check available disk space and ensure sufficient space for estimated output.

**Implementation Requirements:**

```elixir
@doc """
Checks if sufficient disk space is available for crawl.

Estimates required space based on page count and average markdown size.
Returns :ok or {:error, :insufficient_disk_space, required_mb, available_mb}.
"""
@spec check_disk_space(String.t(), pos_integer(), Keyword.t()) ::
        :ok | {:error, :insufficient_disk_space, pos_integer(), pos_integer()}
def check_disk_space(output_dir, estimated_pages, opts \\ []) do
  # Get available space (OS-specific)
  available_mb = get_available_disk_space(output_dir)

  # Estimate required space (configurable)
  avg_page_size_kb = Keyword.get(opts, :avg_page_size_kb, 50)
  safety_multiplier = Keyword.get(opts, :safety_multiplier, 2.0)
  required_mb = round(estimated_pages * avg_page_size_kb * safety_multiplier / 1024)

  max_disk_usage_mb = Keyword.get(opts, :max_disk_usage_mb)

  # Check if we have enough space
  sufficient_space =
    if max_disk_usage_mb do
      available_mb >= required_mb and required_mb <= max_disk_usage_mb
    else
      available_mb >= required_mb
    end

  if sufficient_space do
    :ok
  else
    {:error, :insufficient_disk_space, required_mb, available_mb}
  end
end
```

**Integration Points:**
- Before starting crawl in `mix crawl` task
- After URL discovery when page count is known

**Test Cases:**
- [ ] Sufficient space allows crawl to proceed
- [ ] Insufficient space blocks crawl with clear error
- [ ] Error message includes required and available space
- [ ] Max disk usage option is enforced
- [ ] Works on different filesystems (Linux, macOS, Windows)
- [ ] Safety multiplier provides adequate buffer

---

## 5. Robustness Requirements

### 5.1 File Descriptor Limit Monitoring

#### Requirement 5.1.1: Check File Descriptor Limits

**Priority:** MEDIUM
**System Stability Impact:** MEDIUM

MUST check file descriptor limits before starting crawl and adjust `max_workers` if needed.

**Implementation Requirements:**

```elixir
@doc """
Checks if system has sufficient file descriptors for crawl.

Returns recommended max_workers value or error if insufficient.
"""
@spec check_file_descriptor_limits(pos_integer()) ::
        {:ok, pos_integer()} | {:error, :insufficient_file_descriptors}
def check_file_descriptor_limits(requested_workers) do
  # Get OS file descriptor limits
  {:ok, soft_limit, _hard_limit} = get_fd_limits()

  # Each worker needs: HTTP connection + file handle + overhead
  # Conservative estimate: 5 FD per worker
  max_safe_workers = div(soft_limit, 10)  # Leave 50% headroom

  if requested_workers > max_safe_workers do
    Logger.warn(
      "Requested #{requested_workers} workers exceeds safe limit of #{max_safe_workers}, reducing to #{max_safe_workers}"
    )
    {:ok, max_safe_workers}
  else
    {:ok, requested_workers}
  end
end
```

**Integration Points:**
- Before starting crawl
- Adjust `max_workers` option if necessary

**Test Cases:**
- [ ] Excessive workers are reduced automatically
- [ ] Reasonable workers are unchanged
- [ ] Warning is logged when reducing workers
- [ ] Works on different OS (Linux, macOS, Windows)
- [ ] Handles edge case of very low FD limits

### 5.2 Interrupt Handling

#### Requirement 5.2.1: Graceful Shutdown on Interrupt

**Priority:** HIGH
**Data Integrity Impact:** HIGH

MUST handle interrupt signals (SIGINT, SIGTERM) gracefully:
1. Stop accepting new URLs
2. Complete in-progress writes
3. Clean up partial files (optional, with flag)
4. Report final status

**Implementation Requirements:**

```elixir
defp setup_interrupt_handler(output_dir, cleanup_on_fail?) do
  Process.flag(:trap_exit, true)

  pid = self()

  spawn(fn ->
    receive do
      {:EXIT, ^pid, :interrupt} ->
        Logger.info("Crawl interrupted, cleaning up...")
        if cleanup_on_fail?, do: cleanup_partial_files(output_dir)
        System.stop(1)
    end
  end)
end

defp cleanup_partial_files(output_dir) do
  # Option 1: Use temp files and rename on completion
  # Option 2: Detect incomplete files (e.g., no "---" footer for combined)
  # Option 3: Maintain list of successfully written files and remove others
end
```

**Integration Points:**
- Crawler task setup
- Orchestrator shutdown handling

**Test Cases:**
- [ ] Ctrl+C during crawl stops gracefully
- [ ] Partial files are cleaned up when flag is set
- [ ] Resume option skips existing files
- [ ] Final status is reported with correct counts
- [ ] Works on different platforms

#### Requirement 5.2.2: Atomic File Writes

**Priority:** MEDIUM
**Data Integrity Impact:** HIGH

MUST write files atomically to avoid corruption on interrupt:

**Implementation Requirements:**

```elixir
@doc """
Writes file atomically using temporary file strategy.

1. Write to temp file (.tmp extension)
2. Verify write succeeded
3. Rename to final name (atomic on most filesystems)
4. Clean up temp file if rename fails

Returns :ok or {:error, reason}.
"""
@spec write_file_atomic(String.t(), String.t()) :: :ok | {:error, any()}
def write_file_atomic(filepath, content) do
  temp_path = filepath <> ".tmp"

  with :ok <- File.write(temp_path, content),
       true <- File.exists?(temp_path),
       :ok <- File.rename(temp_path, filepath) do
    :ok
  else
    {:error, reason} ->
      File.rm(temp_path)  # Clean up temp file
      {:error, reason}

    false ->
      {:error, :temp_file_not_created}

    {:error, :eexist} = error ->
      # File already exists, handle per overwrite policy
      File.rm(temp_path)
      error
  end
end
```

**Integration Points:**
- All file write operations in markdown export
- Any file write that should be atomic

**Test Cases:**
- [ ] Successful write creates final file
- [ ] Failed write doesn't leave partial file
- [ ] Works on different filesystems (NTFS, ext4, APFS)
- [ ] Interrupt during write doesn't corrupt file
- [ ] Temp file is cleaned up after successful rename
- [ ] Temp file is cleaned up after failed write

### 5.3 Configurable Overwrite Behavior

#### Requirement 5.3.1: Implement Overwrite Policies

**Priority:** MEDIUM
**User Experience Impact:** HIGH

MUST support multiple behaviors when files already exist.

**Implementation Requirements:**

```elixir
@type overwrite_policy :: :skip | :overwrite | :error | :increment

@doc """
Determines what to do when output file already exists.

Policies:
- :skip - Skip writing this file, continue with next
- :overwrite - Replace existing file
- :error - Raise error and stop crawl
- :increment - Create filename-1.md, filename-2.md, etc. (default)

Returns :ok or {:error, reason}.
"""
@spec handle_existing_file(String.t(), String.t(), overwrite_policy(), Keyword.t()) ::
        :ok | {:error, any()}
def handle_existing_file(filepath, content, policy, opts) do
  case File.exists?(filepath) do
    false ->
      write_file_atomic(filepath, content)

    true ->
      case policy do
        :skip ->
          Logger.debug("Skipping existing file: #{filepath}")
          :ok

        :overwrite ->
          Logger.debug("Overwriting existing file: #{filepath}")
          write_file_atomic(filepath, content)

        :error ->
          {:error, :file_exists, filepath}

        :increment ->
          {:ok, unique_filename} = find_incremental_filename(filepath)
          write_file_atomic(unique_filename, content)
      end
  end
end

@doc """
Finds an incrementally numbered filename that doesn't exist.

Uses zero-padded indices for large collision counts.
Format: filename-0001.md, filename-0002.md, etc.

Auto-switches to hash pattern after 1000 collisions.
"""
@spec find_incremental_filename(String.t()) :: {:ok, String.t()}
def find_incremental_filename(filepath) do
  base_name = Path.basename(filepath, Path.extname(filepath))
  extension = Path.extname(filepath)
  directory = Path.dirname(filepath)

  find_unique_index(directory, base_name, extension, 1)
end

defp find_unique_index(directory, base_name, extension, index) when index < 1000 do
  filename = :io_lib.format("~s-~4..0B~s", [base_name, index, extension]) |> to_string()
  full_path = Path.join(directory, filename)

  case File.exists?(full_path) do
    false ->
      {:ok, filename}

    true ->
      find_unique_index(directory, base_name, extension, index + 1)
  end
end

defp find_unique_index(_directory, base_name, extension, _index) do
  Logger.warn("Too many filename collisions (#{_index}), switching to hash pattern")
  # Generate hash-based filename instead
  hash = :crypto.hash(:sha256, base_name) |> Base.encode16(case: :lower) |> String.slice(0, 8)
  {:ok, hash <> extension}
end
```

**Integration Points:**
- All file write operations
- Filename uniqueness checking

**Test Cases:**
- [ ] :skip policy doesn't write file
- [ ] :overwrite policy replaces file
- [ ] :error policy raises exception with clear message
- [ ] :increment policy creates new filename
- [ ] Works with --resume flag
- [ ] Zero-padding works for 100+ collisions
- [ ] Auto-switch to hash after 1000 collisions
- [ ] Warning logged when switching to hash

### 5.4 Filename Length Management

#### Requirement 5.4.1: Enforce Filename Length Limits

**Priority:** MEDIUM
**Compatibility Impact:** HIGH

Generated filenames MUST NOT exceed 255 characters (common filesystem limit), including extension and index suffixes.

**Implementation Requirements:**

```elixir
@max_filename_length 255
@max_base_length 230  # Leave room for extension and suffix

@doc """
Ensures filename is within filesystem limits.

Truncates at word boundary if necessary.

Returns safe filename within 255 character limit.
"""
@spec ensure_length(String.t(), pos_integer()) :: String.t()
def ensure_length(filename, max_length \\ @max_base_length) do
  if byte_size(filename) <= max_length do
    filename
  else
    filename
    |> String.slice(0, max_length)
    |> String.split(~r/[\s-]/)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("-")
  end
end
```

**Integration Points:**
- All filename generation functions
- Before adding collision index suffixes
- After sanitization

**Test Cases:**
- [ ] Very long URLs are truncated properly
- [ ] Truncation happens at word boundary when possible
- [ ] Including extension doesn't exceed 255 chars
- [ ] Collision suffixes don't push over limit
- [ ] Works with multibyte characters (Unicode)
- [ ] byte_size is used (not String.length)

---

## 6. Implementation Details

### 6.1 Module Structure

Create the following new modules:

```
lib/mulberry/util/
  ├── filename.ex          # Filename generation and validation
  └── file_writer.ex     # Atomic file writing operations
```

Modify existing modules:

```
lib/mulberry/
  ├── document.ex          # Add to_markdown/2 to protocol
  └── document/
      ├── web_page.ex     # Implement to_markdown/2
      └── text_file.ex    # Implement to_markdown/2

lib/mix/tasks/
  └── crawl.ex           # Add markdown export options and logic
```

### 6.2 Implementation Phases

#### Phase 0: Security First (CRITICAL - MUST Complete First)
**Estimated Time:** 4-5 hours

**Tasks:**
1. Implement path traversal validation in `Mulberry.Util.Filename`
2. Implement reserved filename handling
3. Implement atomic file writes in `Mulberry.Util.FileWriter`
4. Implement empty sanitization result handling with fallback
5. Write comprehensive security tests
6. Run all security tests and fix issues
7. Verify no security vulnerabilities

**Success Criteria:**
- [ ] All path traversal tests pass
- [ ] All reserved filename tests pass
- [ ] All atomic write tests pass
- [ ] All sanitization tests pass
- [ ] No security warnings from static analysis

#### Phase 1: Document Protocol Extension
**Estimated Time:** 2-3 hours

**Tasks:**
1. Add `to_markdown/2` spec to `Mulberry.Document` protocol
2. Implement for `WebPage` with markdown cleaning
3. Implement for `TextFile`
4. Add unit tests for protocol
5. Run tests: `mix test test/mulberry/document_test.exs`

**Success Criteria:**
- [ ] Protocol function added
- [ ] WebPage implementation returns markdown
- [ ] WebPage returns error when not loaded
- [ ] TextFile implementation returns content
- [ ] All unit tests pass

#### Phase 2: Filename Utility Module
**Estimated Time:** 2-3 hours

**Tasks:**
1. Create `lib/mulberry/util/filename.ex`
2. Implement `from_url/2` with security validation
3. Implement `from_title/2` with security validation
4. Implement `from_hash/2`
5. Implement `sanitize/1` with error handling
6. Implement `ensure_unique/2` with collision handling
7. Implement `ensure_length/2`
8. Implement `check_reserved_filename/1`
9. Implement `validate_no_path_traversal/2`
10. Add comprehensive unit tests
11. Run tests: `mix test test/mulberry/util/filename_test.exs`

**Success Criteria:**
- [ ] All filename generation functions work
- [ ] Security validation prevents path traversal
- [ ] Reserved names are handled
- [ ] Empty results fall back to hash
- [ ] Collision handling works up to 1000+ cases
- [ ] All unit tests pass

#### Phase 3: File Writer Module
**Estimated Time:** 1-2 hours

**Tasks:**
1. Create `lib/mulberry/util/file_writer.ex`
2. Implement `write_file_atomic/2`
3. Add tests for atomic writes
4. Add tests for interrupt scenarios
5. Run tests

**Success Criteria:**
- [ ] Atomic writes work correctly
- [ ] Temp files are cleaned up
- [ ] Interrupts don't corrupt files
- [ ] All tests pass

#### Phase 4: Crawler Task Enhancement
**Estimated Time:** 4-5 hours

**Tasks:**
1. Add all new CLI options to `parse_args/1`
2. Implement `validate_format_options!/1`
3. Implement `validate_pre_flight!/1` for resource checks
4. Modify `handle_results/2` to `handle_results/3`
5. Implement `handle_console_output/1`
6. Implement `handle_jsonl_output/2`
7. Implement `handle_markdown_output/3`
8. Implement `write_markdown_file/5`
9. Implement `write_combined_markdown/5`
10. Add progress reporting
11. Add interrupt handler
12. Add integration tests
13. Run tests

**Success Criteria:**
- [ ] All CLI options parse correctly
- [ ] Format validation works
- [ ] Pre-flight validation checks disk space
- [ ] Markdown files are created correctly
- [ ] Combined files work with TOC
- [ ] Progress reporting works
- [ ] Interrupt handling works
- [ ] All integration tests pass

#### Phase 5: Testing & Documentation
**Estimated Time:** 3-4 hours

**Tasks:**
1. Write integration tests for all scenarios
2. Write scale tests (1000+ pages)
3. Write security tests
4. Manual testing checklist
5. Update `lib/mix/tasks/crawl.ex` @moduledoc
6. Add examples to README.md
7. Run full test suite: `mix test`
8. Run coverage: `mix coveralls.html`
9. Run full check: `mix check`
10. Verify backward compatibility

**Success Criteria:**
- [ ] All tests pass (unit, integration, scale)
- [ ] Test coverage ≥ 95%
- [ ] `mix check` passes
- [ ] Documentation updated
- [ ] Examples tested and working
- [ ] Backward compatibility verified

### 6.3 Code Quality Standards

- **Documentation:** 100% moduledoc coverage, 100% @spec coverage
- **Testing:** 100% coverage for new code
- **Style:** Follow existing codebase conventions
- **Type Specs:** Use `@spec` for all public functions
- **Error Handling:** Return tagged tuples for errors, raise only for unrecoverable errors
- **Logging:** Use appropriate log levels (debug, info, warn, error)
- **Security:** Validate all inputs, sanitize all filenames

---

## 7. Testing Requirements

### 7.1 Unit Tests

#### Document Protocol Tests

**Test File:** `test/mulberry/document_test.exs`

```elixir
describe "to_markdown/2" do
  test "returns markdown for loaded WebPage" do
    markdown_content = "# Test Page\n\nThis is test content."
    web_page = WebPage.new(url: "https://example.com", markdown: markdown_content)

    assert {:ok, ^markdown_content} = Document.to_markdown(web_page)
  end

  test "returns error for WebPage without markdown" do
    web_page = WebPage.new(url: "https://example.com")

    assert {:error, :not_loaded} = Document.to_markdown(web_page)
  end

  test "cleans whitespace when clean_whitespace: true" do
    markdown_content = "# Title\n\n\n\nContent\n\n\n\n"
    web_page = WebPage.new(url: "https://example.com", markdown: markdown_content)

    assert {:ok, cleaned} = Document.to_markdown(web_page, clean_whitespace: true)
    refute String.contains?(cleaned, "\n\n\n")
  end

  test "returns content for TextFile" do
    text_content = "Plain text content"
    text_file = TextFile.new(path: "/path/to/file.txt", content: text_content)

    assert {:ok, ^text_content} = Document.to_markdown(text_file)
  end

  test "removes empty sections when option enabled" do
    markdown_content = "# Title\n\n\n## Subtitle\n\nContent"
    web_page = WebPage.new(url: "https://example.com", markdown: markdown_content)

    assert {:ok, cleaned} = Document.to_markdown(web_page, remove_empty_sections: true)
    refute String.contains?(cleaned, "## Subtitle\n\n\n")
  end
end
```

#### Filename Utility Tests

**Test File:** `test/mulberry/util/filename_test.exs`

```elixir
describe "from_url/2" do
  test "generates filename from URL" do
    assert {:ok, "example.com-path-to-page.md"} =
             Filename.from_url("https://example.com/path/to/page")
  end

  test "prevents path traversal attacks" do
    malicious_url = "https://evil.com/../../../etc/passwd"
    assert {:error, :path_traversal_attempt} = Filename.from_url(malicious_url)
  end

  test "handles root URL" do
    assert {:ok, "example.com.md"} = Filename.from_url("https://example.com")
  end

  test "respects max_length option" do
    long_url = "https://example.com/" <> String.duplicate("very-long-segment/", 50)

    assert {:ok, filename} = Filename.from_url(long_url, max_length: 50)
    assert String.length(filename) <= 50
  end
end

describe "from_title/2" do
  test "generates filename from title" do
    assert {:ok, "my-awesome-page-title.md"} =
             Filename.from_title("My Awesome Page Title")
  end

  test "prevents path traversal attacks" do
    malicious_title = "/etc/passwd"
    assert {:error, :path_traversal_attempt} = Filename.from_title(malicious_title)
  end

  test "handles empty title" do
    assert {:error, :empty_after_sanitization} = Filename.sanitize("!!!")
  end

  test "falls back to hash when sanitization results in empty" do
    {:ok, filename} = Filename.from_title("!!!")
    assert String.match?(filename, ~r/^[a-f0-9]+\.md$/)
  end
end

describe "check_reserved_filename/1" do
  test "handles Windows reserved names" do
    assert {:ok, "_con.md"} = Filename.check_reserved_filename("con.md")
    assert {:ok, "_PRN.md"} = Filename.check_reserved_filename("PRN.md")
  end

  test "leaves normal filenames unchanged" do
    assert {:ok, "normal.md"} = Filename.check_reserved_filename("normal.md")
  end
end

describe "ensure_unique/2" do
  test "returns filename if doesn't exist" do
    tmp_dir = System.tmp_dir!() <> "/mulberry_test_#{:rand.uniform(10000)}"
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    assert {:ok, "new_file.md"} = Filename.ensure_unique(tmp_dir, "new_file.md")
  end

  test "appends index if file exists" do
    tmp_dir = System.tmp_dir!() <> "/mulberry_test_#{:rand.uniform(10000)}"
    File.mkdir_p!(tmp_dir)
    File.touch!(Path.join(tmp_dir, "existing.md"))
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    assert {:ok, "existing-0001.md"} = Filename.ensure_unique(tmp_dir, "existing.md")
  end
end
```

### 7.2 Integration Tests

**Test File:** `test/mix/tasks/crawl_test.exs`

```elixir
describe "markdown format" do
  test "exports pages as markdown files" do
    tmp_dir = System.tmp_dir!() <> "/crawl_test_#{:rand.uniform(10000)}"
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    args = ["--url", "https://example.com", "--format", "markdown", "--output-dir", tmp_dir]

    assert Mix.Tasks.Crawl.run(args) == :ok

    md_files = Path.wildcard(Path.join([tmp_dir, "*.md"]))
    assert length(md_files) > 0

    # Verify file content
    first_file = List.first(md_files)
    content = File.read!(first_file)
    assert String.contains?(content, "---")  # YAML frontmatter
  end

  test "handles path traversal attempts" do
    tmp_dir = System.tmp_dir!() <> "/crawl_test_#{:rand.uniform(10000)}"
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    # Mock a URL that would attempt path traversal
    # Test that it's rejected and doesn't create files outside tmp_dir
  end

  test "checks disk space before crawl" do
    tmp_dir = System.tmp_dir!() <> "/crawl_test_#{:rand.uniform(10000)}"
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    # Mock disk space check to return insufficient space
    # Verify crawl fails with appropriate error
  end

  test "atomic file writes work" do
    tmp_dir = System.tmp_dir!() <> "/crawl_test_#{:rand.uniform(10000)}"
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    # Write files, interrupt during write
    # Verify no corrupted files exist
  end
end
```

### 7.3 Scale Tests

**Test File:** `test/mulberry/scale_test.exs`

```elixir
describe "scale tests" do
  @tag :scale
  test "handles 1000 pages without memory issues" do
    # Generate mock crawl results for 1000 pages
    # Test memory usage during combined file generation
    # Test file descriptor usage
    # Verify all files are created
  end

  @tag :scale
  test "handles filename collisions at scale" do
    # Generate 1000 pages that would all have same filename
    # Verify all are written with incremental indices
    # Verify auto-switch to hash after 1000 collisions
  end
end
```

### 7.4 Security Tests

```elixir
describe "security: path traversal" do
  test "rejects URLs with .. sequences" do
    malicious_url = "https://evil.com/../../../etc/passwd"
    assert {:error, :path_traversal_attempt} = Filename.from_url(malicious_url)
  end

  test "rejects absolute paths in filenames" do
    malicious_title = "/etc/passwd"
    assert {:error, :path_traversal_attempt} = Filename.from_title(malicious_title)
  end

  test "handles symbolic link attacks" do
    # Test with symlinks in path
    # Verify files aren't written outside output directory
  end
end

describe "security: reserved filenames" do
  test "handles Windows reserved names" do
    assert {:ok, "_con.md"} = Filename.from_title("CON")
    assert {:ok, "_prn.md"} = Filename.from_title("PRN")
  end
end
```

### 7.5 Manual Testing Checklist

#### Functional Testing

- [ ] Crawl single URL with markdown export
- [ ] Crawl multiple URLs with markdown export
- [ ] Crawl website with markdown export
- [ ] Crawl from sitemap with markdown export
- [ ] Test all filename patterns (url, title, hash)
- [ ] Test with metadata and without metadata
- [ ] Test combined file mode
- [ ] Test with URL filtering (include/exclude patterns)
- [ ] Test with custom settings (max-workers, rate-limit)

#### Edge Cases

- [ ] Very long URLs (> 200 chars)
- [ ] URLs with special characters
- [ ] Empty page titles
- [ ] Unicode characters in titles
- [ ] Duplicate URLs in crawl list
- [ ] Reserved filenames (CON, PRN, etc.)
- [ ] Filenames that sanitize to empty
- [ ] 100+ filename collisions
- [ ] Pages that fail to load

#### Error Scenarios

- [ ] Non-existent output directory
- [ ] No write permission to output directory
- [ ] Invalid format option
- [ ] Missing output_dir for markdown
- [ ] Conflicting options (--output with markdown format)
- [ ] Disk full (mock)
- [ ] Interrupt during crawl (Ctrl+C)

#### Performance Testing

- [ ] Large crawl (100+ pages)
- [ ] High concurrency (20+ workers)
- [ ] Memory usage during large crawl
- [ ] File I/O bottleneck detection
- [ ] Combined file with 1000+ pages

#### Backward Compatibility

- [ ] Console output still works (default)
- [ ] JSONL output still works
- [ ] Existing options still work
- [ ] No breaking changes to CLI

### 7.6 Test Execution

```bash
# Run all tests
mix test

# Run with coverage
mix coveralls.html

# Run specific test file
mix test test/mulberry/document_test.exs
mix test test/mulberry/util/filename_test.exs
mix test test/mix/tasks/crawl_test.exs

# Run scale tests (requires --include tag)
mix test --include scale

# Run full check suite
mix check
```

---

## 8. API Reference

### 8.1 Document Protocol

```elixir
# Convert document to markdown
Mulberry.Document.to_markdown(document, opts \\ [])

# Options:
#   - clean_whitespace: boolean (default: false)
#   - remove_empty_sections: boolean (default: false)

# Returns:
#   - {:ok, markdown_string}
#   - {:error, reason}

# Examples:
{:ok, markdown} = Mulberry.Document.to_markdown(web_page)
{:ok, cleaned} = Mulberry.Document.to_markdown(web_page, clean_whitespace: true)
```

### 8.2 Filename Utility

```elixir
# Generate filename from URL
Mulberry.Util.Filename.from_url(url, opts \\ [])
# opts: max_length, extension

# Generate filename from title
Mulberry.Util.Filename.from_title(title, opts \\ [])
# opts: max_length, extension

# Generate filename from hash
Mulberry.Util.Filename.from_hash(url, opts \\ [])
# opts: extension, hash_length

# Sanitize string
Mulberry.Util.Filename.sanitize(string)
# Returns: {:ok, sanitized} or {:error, :empty_after_sanitization}

# Check if filename is reserved
Mulberry.Util.Filename.check_reserved_filename(filename)
# Returns: {:ok, safe_filename}

# Ensure unique filename
Mulberry.Util.Filename.ensure_unique(directory, filename)
# Returns: {:ok, unique_filename}

# Validate no path traversal
Mulberry.Util.Filename.validate_no_path_traversal(filepath, output_dir)
# Returns: :ok or {:error, :path_traversal_attempt}

# Examples:
{:ok, filename} = Filename.from_url("https://example.com/page")
# => "example.com-page.md"

{:ok, filename} = Filename.from_title("My Page")
# => "my-page.md"

{:ok, unique} = Filename.ensure_unique("/path/to/dir", "existing.md")
# => "existing-0001.md" (if existing.md exists)
```

### 8.3 File Writer

```elixir
# Write file atomically
Mulberry.Util.FileWriter.write_file_atomic(filepath, content)
# Returns: :ok or {:error, reason}

# Check disk space
Mulberry.Util.FileWriter.check_disk_space(output_dir, estimated_pages, opts)
# Returns: :ok or {:error, :insufficient_disk_space, required_mb, available_mb}

# Check file descriptor limits
Mulberry.Util.FileWriter.check_file_descriptor_limits(requested_workers)
# Returns: {:ok, adjusted_workers} or {:error, :insufficient_file_descriptors}

# Examples:
:ok = FileWriter.write_file_atomic("/path/to/file.md", markdown)
{:ok, safe_workers} = FileWriter.check_file_descriptor_limits(100)
```

---

## 9. Usage Examples

### 9.1 Basic Markdown Export

```bash
# Crawl website, save each page as markdown
mix crawl --url https://example.com --format markdown --output-dir ./crawled

# Output structure:
# crawled/
# ├── example.com.md
# ├── example.com-about.md
# ├── example.com-contact.md
# └── ...
```

### 9.2 Filename Patterns

```bash
# URL-based (default)
mix crawl --url https://example.com --format markdown --output-dir ./crawled --filename-pattern url
# Creates: example.com.md, example.com-about.md, etc.

# Title-based
mix crawl --url https://example.com --format markdown --output-dir ./crawled --filename-pattern title
# Creates: home.md, about-us.md, contact-us.md, etc.

# Hash-based (guaranteed unique)
mix crawl --url https://example.com --format markdown --output-dir ./crawled --filename-pattern hash
# Creates: a1b2c3d4.md, e5f6g7h8.md, etc.
```

### 9.3 Combined File

```bash
# Combine all pages into single markdown file
mix crawl --url https://example.com --format markdown --output-dir ./crawled --combine-files
# Creates: combined.md with TOC and all pages

# Combined without metadata
mix crawl --url https://example.com --format markdown --output-dir ./crawled --combine-files --no-metadata

# Custom combined filename
mix crawl --url https://example.com --format markdown --output-dir ./crawled --combine-files --combined-filename all-pages
# Creates: all-pages.md
```

### 9.4 With Filtering

```bash
# Crawl blog pages only
mix crawl --url https://example.com --format markdown --output-dir ./blog --include-pattern "/blog/"

# Crawl all pages except PDFs
mix crawl --url https://example.com --format markdown --output-dir ./crawled --exclude-pattern "\.pdf$"

# Combined filtering
mix crawl --url https://example.com --format markdown --output-dir ./blog --include-pattern "/blog/" --exclude-pattern "\.pdf$"
```

### 9.5 With Custom Settings

```bash
# High concurrency
mix crawl --url https://example.com --format markdown --output-dir ./crawled --max-workers 20

# Deep crawl
mix crawl --url https://example.com --format markdown --output-dir ./crawled --max-depth 5

# JavaScript-heavy sites
mix crawl --url https://spa-example.com --format markdown --output-dir ./crawled --retriever playwright

# With progress reporting
mix crawl --url https://example.com --format markdown --output-dir ./crawled --progress
# Output: Progress: 10/42 (24%)
```

### 9.6 File Overwrite Behavior

```bash
# Overwrite existing files
mix crawl --url https://example.com --format markdown --output-dir ./crawled --overwrite

# Skip files that already exist
mix crawl --url https://example.com --format markdown --output-dir ./crawled --skip-existing

# Error on existing files
mix crawl --url https://example.com --format markdown --output-dir ./crawled --error-on-exists

# Incremental (default)
mix crawl --url https://example.com --format markdown --output-dir ./crawled
# Creates: file.md, file-0001.md, file-0002.md, etc.
```

### 9.7 Resume and Cleanup

```bash
# Resume from partial crawl
mix crawl --url https://example.com --format markdown --output-dir ./crawled --resume
# Skips existing files, continues crawl

# Clean up on failure
mix crawl --url https://example.com --format markdown --output-dir ./crawled --cleanup-on-fail
# Removes partial files if crawl fails or is interrupted
```

### 9.8 Resource Management

```bash
# Limit disk usage
mix crawl --url https://example.com --format markdown --output-dir ./crawled --max-disk-usage 500
# Stops if using more than 500MB

# Adjust page size estimation
mix crawl --url https://example.com --format markdown --output-dir ./crawled --avg-page-size 100
# Assume 100KB average page size for space estimation

# Rate limit file writes
mix crawl --url https://example.com --format markdown --output-dir ./crawled --file-write-rate 10
# Maximum 10 file writes per second
```

---

## 10. Error Handling

### 10.1 Error Types

| Error Type | Return Value | User Action |
|-------------|---------------|-------------|
| Path traversal attempt | `{:error, :path_traversal_attempt}` | Fix URL or title with invalid characters |
| File already exists | `{:error, :file_exists, filepath}` | Use --overwrite, --skip-existing, or different directory |
| Insufficient disk space | `{:error, :insufficient_disk_space, required_mb, available_mb}` | Free up disk space or use --max-disk-usage |
| Invalid format | `{:error, :invalid_format, format}` | Use console, jsonl, or markdown |
| Missing output_dir | `{:error, :missing_output_dir}` | Specify --output-dir for markdown format |
| Directory creation failed | `{:error, :directory_creation_failed, reason}` | Check permissions and path |
| Write failed | `{:error, :write_failed, reason}` | Check permissions and disk space |
| Insufficient file descriptors | `{:error, :insufficient_file_descriptors}` | Reduce --max-workers or close other processes |
| Not loaded | `{:error, :not_loaded}` | Page failed to load or has no markdown |
| Reserved filename | (handled internally) | System prefixes with "_" automatically |

### 10.2 Error Messages

```bash
# Path traversal error
ERROR: Security violation: Attempted path traversal in filename generation
URL: https://evil.com/../../../etc/passwd

# Insufficient disk space
ERROR: Insufficient disk space
Required: 1500 MB
Available: 500 MB
Please free up disk space or use --max-disk-usage to limit usage

# Missing output directory
ERROR: --output-dir is required when --format markdown is specified
Example: mix crawl --url https://example.com --format markdown --output-dir ./crawled

# File already exists (with --error-on-exists)
ERROR: File already exists: ./crawled/example.com.md
Use --overwrite to replace, --skip-existing to skip, or remove the file

# Invalid format
ERROR: Invalid format: xyz
Must be one of: console, jsonl, markdown
```

### 10.3 Recovery Strategies

**Disk Full:**
```bash
# Option 1: Clean up disk
rm -rf ./crawled/*.old

# Option 2: Limit disk usage
mix crawl --url https://example.com --format markdown --output-dir ./crawled --max-disk-usage 500

# Option 3: Use smaller page size estimate
mix crawl --url https://example.com --format markdown --output-dir ./crawled --avg-page-size 25
```

**Permission Denied:**
```bash
# Check and fix permissions
ls -la ./crawled
chmod 755 ./crawled

# Or use different directory
mix crawl --url https://example.com --format markdown --output-dir ~/crawled
```

**Filename Collisions:**
```bash
# Use hash pattern for guaranteed uniqueness
mix crawl --url https://example.com --format markdown --output-dir ./crawled --filename-pattern hash

# Or overwrite instead of incrementing
mix crawl --url https://example.com --format markdown --output-dir ./crawled --overwrite
```

---

## 11. Performance Considerations

### 11.1 Memory Management

**Streaming for Large Files:**

For combined markdown files with 1000+ pages, use streaming to avoid loading entire content into memory:

```elixir
defp write_combined_file_stream(results, filepath, add_metadata) do
  File.stream!(filepath, [:utf8, :delayed_write, 4096])
  |> Stream.concat([generate_header(results, add_metadata)])
  |> Stream.concat(results |> Stream.map(&page_content(&1, add_metadata)))
  |> Stream.run()
end
```

**Chunk Processing:**

Process pages in chunks for large crawls:

```elixir
defp process_results_in_chunks(results, chunk_size \\ 50) do
  results
  |> Enum.chunk_every(chunk_size)
  |> Enum.each(fn chunk ->
    process_chunk(chunk)
    GC.collect()  # Encourage garbage collection
  end)
end
```

### 11.2 File I/O Optimization

**Concurrent Writes:**

Use async file writes for individual files:

```elixir
defp write_files_async(results, output_dir, opts) do
  results
  |> Task.async_stream(
    fn result ->
      write_single_file(result, output_dir, opts)
    end,
    max_concurrency: Keyword.get(opts, :max_workers, 5)
  )
  |> Enum.to_list()
  |> Enum.each(fn {:ok, status} -> status end)
end
```

**Buffered Writes:**

Enable delayed write for large files:

```elixir
File.write!(filepath, content, [:delayed_write, 8192])
```

### 11.3 Performance Benchmarks

**Expected Performance:**

| Operation | Target Performance | Notes |
|------------|-------------------|--------|
| Filename generation | < 1ms per file | Includes security validation |
| File write (atomic) | < 100ms per file | Depends on disk speed |
| Combined file (1000 pages) | < 10s total | With streaming |
| Memory usage (1000 pages) | < 500MB peak | With streaming enabled |

**Profiling:**

```bash
# Profile filename generation
mix run -e "
  start = System.monotonic_time(:millisecond)
  Enum.each(1..10000, fn _ ->
    Filename.from_url(\"https://example.com/page\")
  end)
  elapsed = System.monotonic_time(:millisecond) - start
  IO.puts(\"Average: #{elapsed / 10000}ms\")
"
```

---

## 12. Acceptance Criteria

The feature will be considered complete when ALL of the following are met:

### Security Requirements (CRITICAL - MUST PASS)

- [ ] Path traversal validation implemented and tested for all filename generation
- [ ] Reserved filenames are handled correctly across all platforms (Windows, Linux, macOS)
- [ ] Empty sanitization results fall back to hash with warning logged
- [ ] All file paths are validated against output directory before write
- [ ] Security tests pass with 100% success rate
- [ ] No security vulnerabilities in static analysis

### Functional Requirements

- [ ] `to_markdown/2` is added to Document protocol
- [ ] `to_markdown/2` is implemented for WebPage
- [ ] `to_markdown/2` is implemented for TextFile
- [ ] `mix crawl --format markdown` works correctly
- [ ] Individual markdown files are created with proper structure
- [ ] Combined markdown file generation works with TOC
- [ ] All filename patterns (url, title, hash) work correctly
- [ ] Filename sanitization works correctly with all edge cases
- [ ] YAML frontmatter is generated correctly with metadata
- [ ] Without metadata option works (no frontmatter)
- [ ] Table of contents is generated correctly in combined mode
- [ ] Page separators are used correctly in combined mode

### Robustness Requirements

- [ ] Atomic file writes prevent corruption
- [ ] Interrupt handling (Ctrl+C) works correctly
- [ ] Partial file cleanup works when --cleanup-on-fail is set
- [ ] Resume capability (--resume) skips existing files correctly
- [ ] Overwrite policies (--overwrite, --skip-existing, --error-on-exists) work
- [ ] Filename collisions are handled up to 1000+ instances
- [ ] Auto-switch to hash pattern after 1000 collisions
- [ ] Disk space is checked before crawl starts
- [ ] Clear error when insufficient disk space
- [ ] File descriptor limits are checked and workers adjusted if needed
- [ ] Max disk usage option is enforced
- [ ] Progress reporting works when enabled

### Testing Requirements

- [ ] All unit tests pass (document protocol, filename utility, file writer)
- [ ] All integration tests pass (crawler task)
- [ ] All security tests pass
- [ ] Scale tests pass (1000+ pages)
- [ ] Manual testing checklist completed
- [ ] Test coverage ≥ 95% for new code
- [ ] Edge cases tested and handled

### Documentation Requirements

- [ ] Task @moduledoc updated with new options
- [ ] All CLI options documented with examples
- [ ] README updated with markdown export examples
- [ ] Code examples tested and working
- [ ] Error messages are clear and actionable

### Quality Standards

- [ ] 100% moduledoc coverage for new modules
- [ ] 100% @spec coverage for public functions
- [ ] Code follows Mulberry conventions
- [ ] No compiler warnings
- [ ] Credo checks pass
- [ ] Code formatted with `mix format`
- [ ] No type check errors

### Backward Compatibility

- [ ] Console output still works (default behavior)
- [ ] JSONL output still works unchanged
- [ ] Existing CLI options work unchanged
- [ ] No breaking changes to public API
- [ ] Existing tests still pass

### Performance

- [ ] Filename generation ≤ 1ms per file
- [ ] File writes don't bottleneck at max concurrency
- [ ] Combined file generation uses streaming for large files
- [ ] Memory usage stays within reasonable bounds (< 500MB peak for 1000 pages)
- [ ] No file descriptor exhaustion

### Final Verification

- [ ] `mix test` passes (all tests)
- [ ] `mix coveralls.html` shows ≥ 95% coverage
- [ ] `mix check` passes with no issues
- [ ] Manual testing completed successfully
- [ ] Code review completed
- [ ] All acceptance criteria signed off

---

## 13. Quick Reference

### 13.1 Command-Line Options

**New Markdown Options:**
```
--format <format>              Output format: console, jsonl, markdown (default: console)
--output-dir <path>            Directory for markdown files (required for markdown)
--filename-pattern <pattern>    Filename pattern: url, title, or hash (default: url)
--combined-filename <name>      Name for combined file (default: combined)
--combine-files                Combine all pages into single markdown file
--add-metadata                 Add crawl metadata to each file (default: true)
--no-metadata                  Disable metadata addition
--overwrite                    Overwrite existing files (default: increment)
--skip-existing                Skip crawling URLs that would overwrite files
--error-on-exists              Raise error if file would be overwritten
--cleanup-on-fail              Remove partially-written files on failure
--resume                      Skip already-written files, continue crawl
--progress                    Show progress bar during file writes
--max-disk-usage <mb>         Maximum disk usage in MB before stopping
--avg-page-size <kb>          Average page size in KB for estimation (default: 50)
--file-write-rate <n>          Maximum file writes per second
--validate-markdown           Check markdown syntax after generation
```

**Existing Options (Unchanged):**
```
--url <url>                   URL to crawl
--urls <path>                  File containing URLs to crawl
--sitemap <domain|url>          Sitemap to crawl from
--max-depth <n>                Maximum crawl depth (default: 3)
--max-workers <n>               Maximum concurrent workers (default: 5)
--rate-limit <n>               Requests per second (default: 1.0)
--retriever <name>            Retriever: req, playwright, scraping_bee
--no-robots                    Disable robots.txt checking
--include-pattern <regex>        Include URLs matching pattern
--exclude-pattern <regex>        Exclude URLs matching pattern
--verbose / -v                 Verbose logging
--quiet / -q                    Suppress progress output
--verbosity <level>             Log level: quiet, normal, verbose, debug
```

### 13.2 Common Workflows

**Quick Start:**
```bash
# Basic markdown export
mix crawl --url https://example.com --format markdown --output-dir ./crawled
```

**Blog Export:**
```bash
# Export only blog posts
mix crawl --url https://example.com --format markdown --output-dir ./blog \
  --include-pattern "/blog/" --max-depth 3 --filename-pattern title
```

**Documentation Crawl:**
```bash
# Crawl documentation with combined output
mix crawl --url https://docs.example.com --format markdown --output-dir ./docs \
  --combine-files --combined-filename full-docs --add-metadata
```

**Large Scale:**
```bash
# Crawl large site with resource limits
mix crawl --url https://example.com --format markdown --output-dir ./crawled \
  --max-workers 10 --max-disk-usage 2000 --progress \
  --cleanup-on-fail --resume
```

### 13.3 File Structures

**Individual File (with metadata):**
```markdown
---
url: https://example.com/about
title: About Us
crawled_at: 2025-01-12T10:30:45Z
---

# About Us

Content here...
```

**Individual File (without metadata):**
```markdown
# About Us

Content here...
```

**Combined File (excerpt):**
```markdown
# Crawl Results

**Source:** https://example.com
**Crawled:** 2025-01-12T10:30:00Z
**Pages:** 42

## Table of Contents

- [Home](#home)
- [About](#about)
...

---

## Home

**URL:** https://example.com
**Title:** Home

# Home

Content...

---

## About

**URL:** https://example.com/about
**Title:** About

# About

Content...
```

### 13.4 Troubleshooting

**"Files not being created"**
- Check that --output-dir is specified
- Verify output directory permissions: `ls -la ./crawled`
- Check for permission errors in logs
- Try with --verbose for more details

**"Out of disk space"**
- Check available space: `df -h .`
- Use --max-disk-usage to limit
- Free up disk space or use different directory

**"Permission denied"**
- Check directory permissions: `ls -la ./crawled`
- Fix permissions: `chmod 755 ./crawled`
- Use a different directory

**"Filename collision warnings"**
- This is normal behavior
- System automatically creates: file-0001.md, file-0002.md
- Or use --filename-pattern hash for guaranteed uniqueness

**"Empty markdown files"**
- Check crawler output for errors
- Verify URLs are accessible
- Try with --verbose for more details

**"Path traversal error"**
- URL or title contains invalid characters
- Fix the source URL or title
- Use --filename-pattern hash as fallback

### 13.5 Testing Commands

```bash
# Run all tests
mix test

# Run with coverage
mix coveralls.html

# Run specific test file
mix test test/mulberry/document_test.exs
mix test test/mulberry/util/filename_test.exs
mix test test/mix/tasks/crawl_test.exs

# Run scale tests
mix test --include scale

# Run full check suite
mix check

# Format code
mix format

# Run linter
mix credo --strict
```

### 13.6 File Locations

**Implementation:**
- `lib/mulberry/document.ex` - Document protocol
- `lib/mulberry/document/web_page.ex` - WebPage implementation
- `lib/mulberry/document/text_file.ex` - TextFile implementation
- `lib/mulberry/util/filename.ex` - Filename utility (new)
- `lib/mulberry/util/file_writer.ex` - File writer (new)
- `lib/mix/tasks/crawl.ex` - Crawler task

**Tests:**
- `test/mulberry/document_test.exs` - Document tests
- `test/mulberry/util/filename_test.exs` - Filename tests (new)
- `test/mulberry/util/file_writer_test.exs` - File writer tests (new)
- `test/mix/tasks/crawl_test.exs` - Crawler tests (new)
- `test/mulberry/scale_test.exs` - Scale tests (new)

### 13.7 Development Workflow

**1. Implementation Order:**
```
Phase 0: Security First (CRITICAL)
  ↓
Phase 1: Document Protocol
  ↓
Phase 2: Filename Utility
  ↓
Phase 3: File Writer
  ↓
Phase 4: Crawler Task
  ↓
Phase 5: Testing & Documentation
```

**2. Quality Checks After Each Phase:**
```bash
mix format
mix credo
mix test
```

**3. Full Check:**
```bash
mix check
```

**4. Commit Pattern:**
```bash
# Phase 0
git add lib/mulberry/util/* test/mulberry/util/*
git commit -m "feat(security): add path traversal and atomic file writes"

# Phase 1
git add lib/mulberry/document.ex lib/mulberry/document/* test/mulberry/document_test.exs
git commit -m "feat(document): add to_markdown/2 protocol function"

# Phase 2
git add lib/mulberry/util/filename.ex test/mulberry/util/filename_test.exs
git commit -m "feat(util): add filename generation with security validation"

# Phase 3
git add lib/mulberry/util/file_writer.ex test/mulberry/util/file_writer_test.exs
git commit -m "feat(util): add atomic file writing operations"

# Phase 4
git add lib/mix/tasks/crawl.ex test/mix/tasks/crawl_test.exs
git commit -m "feat(crawl): add markdown export support to crawler"

# Phase 5
git add README.md
git commit -m "docs: update README with markdown export examples"
```

---

## Appendix A: Implementation Checklist

Use this checklist during implementation:

### Phase 0: Security (CRITICAL - MUST COMPLETE FIRST)
- [ ] Implement path traversal validation
- [ ] Implement reserved filename handling
- [ ] Implement atomic file writes
- [ ] Implement empty sanitization handling with fallback
- [ ] Write security tests
- [ ] Run security tests and fix all issues
- [ ] Verify no security vulnerabilities

### Phase 1: Document Protocol
- [ ] Add `to_markdown/2` spec to Document protocol
- [ ] Implement for WebPage with markdown
- [ ] Implement for WebPage without markdown (error case)
- [ ] Implement for TextFile
- [ ] Add unit tests
- [ ] Run tests: `mix test test/mulberry/document_test.exs`

### Phase 2: Filename Utility
- [ ] Create `Mulberry.Util.Filename` module
- [ ] Implement `from_url/2` with security validation
- [ ] Implement `from_title/2` with security validation
- [ ] Implement `from_hash/2`
- [ ] Implement `sanitize/1` with error handling
- [ ] Implement `ensure_unique/2` with collision handling
- [ ] Implement `ensure_length/2`
- [ ] Implement `check_reserved_filename/1`
- [ ] Implement `validate_no_path_traversal/2`
- [ ] Add unit tests
- [ ] Run tests: `mix test test/mulberry/util/filename_test.exs`

### Phase 3: File Writer
- [ ] Create `Mulberry.Util.FileWriter` module
- [ ] Implement `write_file_atomic/2`
- [ ] Implement `check_disk_space/3`
- [ ] Implement `check_file_descriptor_limits/1`
- [ ] Add tests for atomic writes
- [ ] Add tests for resource checks
- [ ] Run tests

### Phase 4: Crawler Task
- [ ] Add `--format` option
- [ ] Add `--output-dir` option
- [ ] Add `--filename-pattern` option
- [ ] Add `--combined-filename` option
- [ ] Add `--combine-files` option
- [ ] Add `--add-metadata` option
- [ ] Add `--no-metadata` option
- [ ] Add `--overwrite` option
- [ ] Add `--skip-existing` option
- [ ] Add `--error-on-exists` option
- [ ] Add `--cleanup-on-fail` option
- [ ] Add `--resume` option
- [ ] Add `--progress` option
- [ ] Add `--max-disk-usage` option
- [ ] Add `--avg-page-size` option
- [ ] Add `--file-write-rate` option
- [ ] Add `--validate-markdown` option
- [ ] Implement format validation
- [ ] Implement pre-flight validation
- [ ] Refactor `handle_results/2` to `handle_results/3`
- [ ] Implement markdown output logic
- [ ] Implement individual file writing
- [ ] Implement combined file generation
- [ ] Implement YAML frontmatter generation
- [ ] Implement table of contents
- [ ] Implement progress reporting
- [ ] Implement interrupt handler
- [ ] Add error handling
- [ ] Add integration tests
- [ ] Run tests: `mix test test/mix/tasks/crawl_test.exs`

### Phase 5: Testing & Documentation
- [ ] Add integration tests
- [ ] Add scale tests (1000+ pages)
- [ ] Add security tests
- [ ] Test error scenarios
- [ ] Manual testing checklist
- [ ] Update task @moduledoc
- [ ] Add examples to README
- [ ] Run all tests: `mix test`
- [ ] Run coverage: `mix coveralls.html`
- [ ] Run full check: `mix check`
- [ ] Verify backward compatibility

### Final Verification
- [ ] All acceptance criteria met
- [ ] All tests passing
- [ ] Coverage ≥ 95%
- [ ] `mix check` passing
- [ ] Documentation complete
- [ ] Code review completed
- [ ] Security review completed
- [ ] Manual testing completed

---

## Appendix B: Glossary

- **JSONL:** JSON Lines format (one JSON object per line)
- **Frontmatter:** Metadata section at the top of a markdown file, delimited by `---`
- **Sanitization:** Process of removing or replacing special characters in filenames
- **Protocol:** Elixir's protocol system for polymorphic behavior
- **Retriever:** Module responsible for fetching content from URLs
- **Crawl Depth:** Maximum number of link levels to follow from starting URL
- **Rate Limiting:** Throttling requests to avoid overwhelming target servers
- **Atomic Write:** File write operation that either completes fully or not at all (using temp file + rename)
- **Path Traversal:** Security attack where malicious input attempts to escape intended directory
- **Reserved Filename:** Filename that has special meaning to operating system (CON, PRN, etc.)
- **Whitespace Cleaning:** Removing excessive newlines and whitespace-only lines
- **Empty Section:** Markdown heading with little or no content under it

---

**End of Specification**
