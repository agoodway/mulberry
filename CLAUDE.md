# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mulberry is an AI package for Elixir focusing on document processing, AI-powered text analysis, and search capabilities. The project is in "Very Alpha" stage and uses a protocol-based architecture for extensibility.

## Architecture

The codebase follows a protocol-based design with functional composition patterns:

- **Document Protocol** (`Mulberry.Document`): Core abstraction for all document types (WebPage, File). All document operations (load, generate_summary, to_text, etc.) are defined here.
- **Retriever Behavior** (`Mulberry.Retriever`): Defines how content is fetched from URLs. Implementations include Req (HTTP), Playwright (browser-based), and ScrapingBee (API service).
- **Search Behavior** (`Mulberry.Search.Behaviour`): Extensible search interface, currently implemented for Brave Search API.
- **Functional Composition**: Uses Flamel library for chaining operations via `Chain.apply/2`.

## Essential Commands

```bash
# Development workflow
mix deps.get              # Install dependencies
mix test                  # Run tests
mix check                 # Run full check suite (compile warnings, credo, doctor, tests, coverage)
mix check.coverage        # Generate HTML coverage report
mix format               # Format code
mix credo                # Static code analysis
mix doctor               # Documentation coverage check

# Run a single test file
mix test test/document/text_file_test.exs

# Run tests with coverage
mix coveralls.html       # Generate HTML coverage report in cover/
```

## Required Environment Variables

```bash
OPENAI_API_KEY=your_key_here    # Required for AI features (summarization, title generation)
BRAVE_API_KEY=your_key_here     # Required for Brave search functionality
```

## External Dependencies

- **Tesseract OCR**: Required for image text extraction (`ocr_image/1` functions)
- **Playwright**: Required for JavaScript-heavy web scraping (browser automation)

## Key Implementation Details

1. **Document Loading**: The `Document.load/2` function dispatches based on MIME type. PDFs and images use OCR, while text files are read directly.

2. **AI Integration**: Text processing functions in `Mulberry.Text` accept options for custom LLMs:
   ```elixir
   Mulberry.Text.summarize(text, llm: custom_llm, system_message: "Custom prompt")
   ```

3. **Retriever Pattern**: Multiple retrievers can be tried in sequence:
   ```elixir
   Mulberry.Retriever.get([Req, Playwright], url, opts)
   ```

4. **File Type Support**: Currently supports text/plain, PDFs, and common image formats (PNG, JPEG, GIF, WebP, TIFF) via OCR.

## Testing Conventions

- Tests use Mimic for mocking (configured in `test/test_helper.exs`)
- Modules available for mocking: `Mulberry.Retriever`, `Mulberry.Retriever.Req`, `Mulberry.Retriever.Playwright`, `Mulberry.Retriever.ScrapingBee`

## Code Quality Standards

- 100% documentation coverage enforced by mix doctor
- 100% spec coverage for all public functions
- Credo configured for code quality checks
- All checks must pass before committing (run `mix check`)


### Coding Rules

- Whenever you think your finished making a change the user requested, run a `mix check` to check for compilation errors, test regressions, and code quality
- When adding a *large* feature or change, it's a good idea to add a test as well. If your making small little changes
you can use your best judgement as to whether a test is needed or not.
- When adding tests make sure to make them async if you can.
- Please make sure to fill in the `@moduledoc` attribute for modules.
- Please make sure to add @spec for every function
- Use Faker when generating test data and seed data
- Use ExUnit.CaptureLog if there are any errors getting logged in tests

YOU MUST use conventional commits when writing commit messages
<type>[scope]: <description>\n\n[body]\n\n[footer(s)]
Type: feat(MINOR), fix(PATCH), or build/chore/ci/docs/style/refactor/perf/test. Req. Scope: Opt, (noun). Desc: Short summary post : . Req. Body: Opt, blank line + paras. Footer: Opt, blank line + token: value/token#value.
Breaking (MAJOR): type[!scope]!: desc or BREAKING CHANGE: desc. Rules: Case-insensitive, except BREAKING CHANGE. feat=feature, fix=bug.
ex:
feat: config extend\n\nBREAKING CHANGE: extends key configs
feat!: email ship
docs: fix CHANGELOG
fix: stop race\n\nAdd ID.\n\nReviewed-by: Z
