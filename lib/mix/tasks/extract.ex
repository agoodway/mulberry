defmodule Mix.Tasks.Extract do
  @moduledoc """
  Extracts structured data from text, files, or URLs using a JSON schema.

  This task uses Mulberry's data extraction capabilities to parse unstructured
  text and extract specific information based on a provided schema definition.

  ## Usage

      mix extract [OPTIONS]

  ## Input Options (one required)

    * `--text` - Text to extract data from
    * `--file` - Read text from a file
    * `--url` - Fetch content from URL and extract data

  ## Schema Options (one required)

    * `--schema` - JSON string defining the extraction schema
    * `--schema-file` - Read schema from a JSON file

  ## Retriever Options (for --url)

    * `--retriever` - Retriever to use: req (default), playwright, scrapingbee
    * `--browser` - Browser for Playwright: chromium (default), firefox, webkit
    * `--headless` - Run browser in headless mode (default: true)
    * `--wait-for` - CSS selector to wait for (Playwright)
    * `--timeout` - Request timeout in milliseconds (default: 30000)
    * `--stealth` - Enable stealth mode for Playwright (default: true)

  ## LLM Options

    * `--provider` - LLM provider (openai, anthropic, google, etc.)
    * `--model` - Model to use for the provider
    * `--temperature` - Temperature setting (0.0-1.0)
    * `--api-key` - API key for the provider

  ## Output Options

    * `--output` - Output format: text (default), json
    * `--pretty` - Pretty print JSON output
    * `--save` - Save output to file
    * `--verbose` - Enable verbose output

  ## Examples

      # Extract from text with inline schema
      mix extract --text "John Smith, 32, works as an engineer at TechCorp" \\
        --schema '{"type":"object","properties":{"name":{"type":"string"},"age":{"type":"number"},"occupation":{"type":"string"},"company":{"type":"string"}}}'

      # Extract from file using schema file
      mix extract --file article.txt --schema-file person_schema.json

      # Extract from URL with default retriever
      mix extract --url https://example.com/team \\
        --schema-file employee_schema.json --save employees.json

      # Extract from URL using Playwright
      mix extract --url https://example.com \\
        --schema '{"type":"object","properties":{"title":{"type":"string"},"price":{"type":"number"}}}' \\
        --retriever playwright --browser firefox --wait-for ".content"

      # Extract with specific LLM provider
      mix extract --file data.txt --schema-file schema.json \\
        --provider anthropic --model claude-3-haiku --output json --pretty

      # Extract multiple items from text
      mix extract --text "Product A costs $10. Product B is $15.50." \\
        --schema '{"type":"object","properties":{"product":{"type":"string"},"price":{"type":"number"}}}' \\
        --output json

  ## Schema Format

  The schema should be a JSON object following this structure:

      {
        "type": "object",
        "properties": {
          "field_name": {
            "type": "string|number|boolean|array",
            "description": "Optional description to help extraction"
          }
        },
        "required": ["field1", "field2"]  // Optional
      }

  The extraction will return an array of objects matching the schema,
  as it can extract multiple instances from a single text.
  """

  use Mix.Task
  import Mix.Shell.IO

  @shortdoc "Extracts structured data from text using a JSON schema"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = parse_args(args)

    # Start the application
    Mix.Task.run("app.start")

    # Validate input options
    validate_options(opts)

    # Get input text
    text = get_input_text(opts)

    # Get schema
    schema = get_schema(opts)

    # Extract data
    info("Extracting data...")
    extract_and_output(text, schema, opts)
  rescue
    e ->
      error("Error: #{Exception.message(e)}")
      exit({:shutdown, 1})
  end

  defp parse_args(args) do
    OptionParser.parse(args,
      strict: [
        # Input options
        text: :string,
        file: :string,
        url: :string,
        # Schema options
        schema: :string,
        schema_file: :string,
        # Retriever options
        retriever: :string,
        browser: :string,
        headless: :boolean,
        wait_for: :string,
        timeout: :integer,
        stealth: :boolean,
        # LLM options
        provider: :string,
        model: :string,
        temperature: :float,
        api_key: :string,
        # Output options
        output: :string,
        pretty: :boolean,
        save: :string,
        verbose: :boolean
      ],
      aliases: [
        t: :text,
        f: :file,
        u: :url,
        s: :schema,
        r: :retriever,
        p: :provider,
        m: :model,
        o: :output,
        v: :verbose
      ]
    )
  end

  defp validate_options(opts) do
    # Check input source
    input_count = Enum.count([:text, :file, :url], &Keyword.has_key?(opts, &1))

    if input_count == 0 do
      Mix.raise("You must provide one of: --text, --file, or --url")
    end

    if input_count > 1 do
      Mix.raise("You can only provide one input source: --text, --file, or --url")
    end

    # Check schema source
    schema_count = Enum.count([:schema, :schema_file], &Keyword.has_key?(opts, &1))

    if schema_count == 0 do
      Mix.raise("You must provide either --schema or --schema-file")
    end

    if schema_count > 1 do
      Mix.raise("You can only provide one schema source: --schema or --schema-file")
    end

    # Validate retriever option
    if opts[:retriever] && opts[:retriever] not in ["req", "playwright", "scrapingbee"] do
      Mix.raise(
        "Invalid retriever: #{opts[:retriever]}. Must be one of: req, playwright, scrapingbee"
      )
    end

    # Validate output format
    if opts[:output] && opts[:output] not in ["text", "json"] do
      Mix.raise("Invalid output format: #{opts[:output]}. Must be: text or json")
    end
  end

  defp get_input_text(opts) do
    cond do
      opts[:text] ->
        opts[:text]

      opts[:file] ->
        if opts[:verbose], do: info("Reading from file: #{opts[:file]}")
        File.read!(opts[:file])

      opts[:url] ->
        fetch_from_url(opts[:url], opts)
    end
  end

  defp fetch_from_url(url, opts) do
    info("Fetching content from: #{url}")

    # Create a WebPage document
    web_page = Mulberry.Document.WebPage.new(%{url: url})

    # Build retriever options
    retriever_opts = build_retriever_opts(opts)

    # Load the document
    case Mulberry.Document.load(web_page, retriever_opts) do
      {:ok, loaded_page} ->
        extract_text_from_document(loaded_page, opts)

      {:error, reason, _} ->
        Mix.raise("Failed to fetch URL: #{inspect(reason)}")
    end
  end

  defp extract_text_from_document(loaded_page, opts) do
    case Mulberry.Document.to_text(loaded_page) do
      {:ok, text} ->
        if opts[:verbose], do: info("Successfully fetched #{String.length(text)} characters")
        text

      {:error, reason} ->
        Mix.raise("Failed to extract text from URL: #{inspect(reason)}")
    end
  end

  defp build_retriever_opts(opts) do
    retriever_opts = []

    # Set retriever module
    retriever_opts =
      if opts[:retriever] do
        retriever_module =
          case opts[:retriever] do
            "req" -> Mulberry.Retriever.Req
            "playwright" -> Mulberry.Retriever.Playwright
            "scrapingbee" -> Mulberry.Retriever.ScrapingBee
            _ -> Mulberry.Retriever.Req
          end

        Keyword.put(retriever_opts, :retriever, retriever_module)
      else
        retriever_opts
      end

    # Add Playwright-specific options
    retriever_opts =
      retriever_opts
      |> maybe_add_option(:browser, opts[:browser])
      |> maybe_add_option(:headless, opts[:headless])
      |> maybe_add_option(:wait_for, opts[:wait_for])
      |> maybe_add_option(:timeout, opts[:timeout])
      |> maybe_add_option(:stealth, opts[:stealth])

    if opts[:verbose] && retriever_opts != [] do
      info("Retriever options: #{inspect(retriever_opts)}")
    end

    retriever_opts
  end

  defp get_schema(opts) do
    json_string =
      cond do
        opts[:schema] ->
          opts[:schema]

        opts[:schema_file] ->
          if opts[:verbose], do: info("Reading schema from: #{opts[:schema_file]}")
          File.read!(opts[:schema_file])
      end

    case Jason.decode(json_string) do
      {:ok, schema} ->
        if opts[:verbose], do: info("Schema loaded successfully")
        schema

      {:error, error} ->
        Mix.raise("Invalid JSON in schema: #{inspect(error)}")
    end
  end

  defp extract_and_output(text, schema, opts) do
    # Build extraction options
    extract_opts =
      build_extract_opts(opts)
      |> Keyword.put(:schema, schema)

    # Perform extraction
    case Mulberry.Text.extract(text, extract_opts) do
      {:ok, extracted_data} ->
        handle_success(extracted_data, opts)

      {:error, reason} ->
        Mix.raise("Extraction failed: #{inspect(reason)}")
    end
  end

  defp build_extract_opts(opts) do
    []
    |> maybe_add_option(:provider, opts[:provider], &String.to_atom/1)
    |> maybe_add_option(:model, opts[:model])
    |> maybe_add_option(:temperature, opts[:temperature])
    |> maybe_add_option(:api_key, opts[:api_key])
    |> maybe_add_option(:verbose, opts[:verbose])
  end

  defp handle_success(extracted_data, opts) do
    output_format = opts[:output] || "text"

    output =
      case output_format do
        "json" -> format_json_output(extracted_data, opts)
        "text" -> format_text_output(extracted_data)
      end

    # Display output
    info(output)

    # Save if requested
    if opts[:save] do
      File.write!(opts[:save], output)
      info("\nOutput saved to: #{opts[:save]}")
    end
  end

  defp format_json_output(data, opts) do
    if opts[:pretty] do
      Jason.encode!(data, pretty: true)
    else
      Jason.encode!(data)
    end
  end

  defp format_text_output([]) do
    "No data extracted matching the schema."
  end

  defp format_text_output(data) when is_list(data) do
    data
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {item, index} ->
      header = "=== Item #{index} ==="

      fields =
        Enum.map_join(item, "\n", fn {key, value} ->
          "#{key}: #{format_value(value)}"
        end)

      "#{header}\n#{fields}"
    end)
  end

  defp format_value(value) when is_list(value), do: Enum.join(value, ", ")
  defp format_value(value), do: to_string(value)

  defp maybe_add_option(opts, _key, nil), do: opts
  defp maybe_add_option(opts, key, value), do: Keyword.put(opts, key, value)
  defp maybe_add_option(opts, _key, nil, _transform), do: opts

  defp maybe_add_option(opts, key, value, transform),
    do: Keyword.put(opts, key, transform.(value))
end
