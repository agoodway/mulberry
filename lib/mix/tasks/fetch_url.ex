defmodule Mix.Tasks.FetchUrl do
  @moduledoc """
  Fetches a URL using the Playwright retriever.

  ## Usage

      mix fetch_url URL [options]

  ## Options

    * `--headless` - Run browser in headless mode (default: true)
    * `--browser` - Browser type: chromium, firefox, or webkit (default: chromium)
    * `--stealth` - Enable stealth mode (default: true)
    * `--timeout` - Timeout in milliseconds (default: 30000)
    * `--wait-for` - CSS selector to wait for (default: body)
    * `--save` - Save HTML content to specified file
    * `--show-text` - Show extracted text content instead of HTML
    * `--markdown` - Convert HTML to Markdown format

  ## Examples

      # Basic usage
      mix fetch_url https://example.com

      # Save to file
      mix fetch_url https://example.com --save output.html

      # Use Firefox in non-headless mode (visible browser)  
      mix fetch_url https://example.com --browser firefox --no-headless

      # Show text content only
      mix fetch_url https://example.com --show-text

      # Convert to Markdown
      mix fetch_url https://example.com --markdown

      # Save as Markdown file
      mix fetch_url https://example.com --markdown --save output.md

      # Wait for specific element
      mix fetch_url https://example.com --wait-for "#content"
  """

  use Mix.Task

  @shortdoc "Fetches a URL using Playwright retriever"

  @impl Mix.Task
  def run(args) do
    {opts, [url | _], _} = OptionParser.parse(args,
      switches: [
        headless: :boolean,
        browser: :string,
        stealth: :boolean,
        timeout: :integer,
        wait_for: :string,
        save: :string,
        show_text: :boolean,
        markdown: :boolean
      ],
      aliases: [
        h: :headless,
        b: :browser,
        s: :stealth,
        t: :timeout,
        w: :wait_for,
        m: :markdown
      ]
    )

    unless url do
      Mix.raise("URL is required. Usage: mix fetch_url URL [options]")
    end

    # Start the application
    Mix.Task.run("app.start")

    # Build retriever options
    retriever_opts = build_retriever_opts(opts)

    Mix.shell().info("Fetching URL: #{url}")
    Mix.shell().info("Options: #{inspect(retriever_opts)}")
    Mix.shell().info("")

    # Fetch the URL
    result = Mulberry.Retriever.Playwright.get(url, retriever_opts)

    IO.inspect(result: result)
    
    case result do
      {:ok, %Mulberry.Retriever.Response{status: :ok, content: html}} ->
        handle_success(html, opts)
      
      %Mulberry.Retriever.Response{status: :ok, content: html} ->
        handle_success(html, opts)
        
      {:ok, %Mulberry.Retriever.Response{status: :failed}} ->
        Mix.shell().error("Failed to fetch URL")
        exit({:shutdown, 1})
      
      %Mulberry.Retriever.Response{status: :failed} ->
        Mix.shell().error("Failed to fetch URL")
        exit({:shutdown, 1})
      
      other ->
        Mix.shell().error("Unexpected response: #{inspect(other)}")
        exit({:shutdown, 1})
    end
  end

  defp build_retriever_opts(opts) do
    retriever_opts = []

    retriever_opts = 
      if Keyword.has_key?(opts, :headless) do
        Keyword.put(retriever_opts, :headless, opts[:headless])
      else
        retriever_opts
      end

    retriever_opts =
      if browser = opts[:browser] do
        browser_atom = String.to_existing_atom(browser)
        if browser_atom in [:chromium, :firefox, :webkit] do
          Keyword.put(retriever_opts, :browser, browser_atom)
        else
          Mix.raise("Invalid browser: #{browser}. Must be chromium, firefox, or webkit")
        end
      else
        retriever_opts
      end

    retriever_opts =
      if Keyword.has_key?(opts, :stealth) do
        Keyword.put(retriever_opts, :stealth_mode, opts[:stealth])
      else
        retriever_opts
      end

    retriever_opts =
      if timeout = opts[:timeout] do
        Keyword.put(retriever_opts, :timeout, timeout)
      else
        retriever_opts
      end

    retriever_opts =
      if wait_for = opts[:wait_for] do
        Keyword.put(retriever_opts, :wait_for_selector, wait_for)
      else
        retriever_opts
      end

    retriever_opts
  end

  defp handle_success(html, opts) do
    cond do
      opts[:markdown] && opts[:save] ->
        save_as_markdown(html, opts[:save])
      
      opts[:save] ->
        save_to_file(html, opts[:save])
      
      opts[:markdown] ->
        show_markdown_content(html)
        
      opts[:show_text] ->
        show_text_content(html)
      
      true ->
        show_html_preview(html)
    end
  end

  defp save_to_file(html, path) do
    case File.write(path, html) do
      :ok ->
        Mix.shell().info("HTML content saved to: #{path}")
        Mix.shell().info("File size: #{byte_size(html)} bytes")
      
      {:error, reason} ->
        Mix.shell().error("Failed to save file: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp show_text_content(html) do
    # Parse HTML and convert to readable text
    text = 
      html
      |> Floki.parse_document!()
      |> Mulberry.HTML.to_readable_text()
      |> String.trim()
    
    Mix.shell().info("Extracted text content:")
    Mix.shell().info("=" <> String.duplicate("=", 79))
    Mix.shell().info(text)
    Mix.shell().info("=" <> String.duplicate("=", 79))
    Mix.shell().info("Text length: #{String.length(text)} characters")
  end

  defp show_markdown_content(html) do
    case Mulberry.HTML.to_markdown(html) do
      {:ok, markdown} ->
        Mix.shell().info("Markdown content:")
        Mix.shell().info("=" <> String.duplicate("=", 79))
        Mix.shell().info(markdown)
        Mix.shell().info("=" <> String.duplicate("=", 79))
        Mix.shell().info("Markdown length: #{String.length(markdown)} characters")
        
      {:error, reason} ->
        Mix.shell().error("Failed to convert to Markdown: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp save_as_markdown(html, path) do
    case Mulberry.HTML.to_markdown(html) do
      {:ok, markdown} ->
        case File.write(path, markdown) do
          :ok ->
            Mix.shell().info("Markdown content saved to: #{path}")
            Mix.shell().info("File size: #{byte_size(markdown)} bytes")
          
          {:error, reason} ->
            Mix.shell().error("Failed to save file: #{inspect(reason)}")
            exit({:shutdown, 1})
        end
        
      {:error, reason} ->
        Mix.shell().error("Failed to convert to Markdown: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp show_html_preview(html) do
    # Show first 1000 characters of HTML
    preview_length = 1000
    preview = 
      if byte_size(html) > preview_length do
        String.slice(html, 0, preview_length) <> "\n... (truncated)"
      else
        html
      end

    Mix.shell().info("HTML content preview:")
    Mix.shell().info("=" <> String.duplicate("=", 79))
    Mix.shell().info(preview)
    Mix.shell().info("=" <> String.duplicate("=", 79))
    Mix.shell().info("Total HTML size: #{byte_size(html)} bytes")
    
    # Extract and show title
    case Regex.run(~r/<title[^>]*>([^<]+)<\/title>/i, html) do
      [_, title] -> Mix.shell().info("Page title: #{String.trim(title)}")
      _ -> Mix.shell().info("Page title: (not found)")
    end
  end
end
