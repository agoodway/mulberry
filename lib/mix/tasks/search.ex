defmodule Mix.Tasks.Search do
  @moduledoc """
  Performs searches using various providers.

  ## Usage

      mix search [TYPE] QUERY [options]

  ## Search Types

    * `brave` - Web search using Brave Search API (default)
    * `reddit` - Reddit post search using ScrapeCreators API

  ## Common Options

    * `--limit` - Maximum number of results (default: 10)
    * `--format` - Output format: text, json, or markdown (default: text)
    * `--save` - Save results to specified file
    * `--verbose` - Show detailed information

  ## Provider-Specific Options

  ### Brave Search

    * `--result-filter` - Filter results, e.g., "query,web" (default: "query,web")

  ### Reddit Search

    * `--sort` - Sort order: relevance, hot, top, new, comments
    * `--timeframe` - Time filter: all, year, month, week, day, hour
    * `--subreddit` - Filter by specific subreddit
    * `--after` - Pagination token for next page
    * `--trim` - Get trimmed responses (boolean)

  ## Examples

      # Default Brave search
      mix search "elixir programming"

      # Explicit Brave search
      mix search brave "phoenix framework"

      # Reddit search
      mix search reddit "machine learning"

      # Reddit search with options
      mix search reddit "elixir tips" --sort top --timeframe month

      # Save results as JSON
      mix search reddit "web scraping" --format json --save results.json

      # Filter by subreddit
      mix search reddit "tips" --subreddit elixir

      # Verbose mode with limit
      mix search brave "phoenix liveview" --verbose --limit 5
  """

  use Mix.Task

  @shortdoc "Performs searches using various providers"

  @search_modules %{
    "brave" => Mulberry.Search.Brave,
    "reddit" => Mulberry.Search.Reddit
  }

  @impl Mix.Task
  def run(args) do
    {opts, args_list, _} = OptionParser.parse(args,
      switches: [
        limit: :integer,
        format: :string,
        save: :string,
        verbose: :boolean,
        result_filter: :string,
        sort: :string,
        timeframe: :string,
        subreddit: :string,
        after: :string,
        trim: :boolean
      ],
      aliases: [
        l: :limit,
        f: :format,
        v: :verbose,
        s: :sort,
        t: :timeframe
      ]
    )

    # Parse type and query from args
    {type, query} = parse_arguments(args_list)
    
    unless query && String.trim(query) != "" do
      Mix.raise("Query is required. Usage: mix search [TYPE] QUERY [options]")
    end

    # Start the application
    Mix.Task.run("app.start")

    # Validate options
    opts = validate_options(opts, type)
    
    # Get search module
    search_module = get_search_module(type)
    
    # Check API key
    check_api_key(type)

    if opts[:verbose] do
      Mix.shell().info("Search type: #{type}")
      Mix.shell().info("Query: #{query}")
      Mix.shell().info("Options: #{inspect(opts)}")
      Mix.shell().info("")
    end

    # Perform search
    result = perform_search(search_module, query, opts)
    
    case result do
      {:ok, documents} ->
        handle_success(documents, opts, type)
        
      {:error, reason} ->
        Mix.shell().error("Search failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp parse_arguments([]), do: {"brave", nil}
  defp parse_arguments([query]), do: {"brave", query}
  defp parse_arguments([type, query | rest]) do
    if Map.has_key?(@search_modules, type) do
      # First arg is a valid type
      {type, Enum.join([query | rest], " ")}
    else
      # First arg is not a type, treat everything as query
      {"brave", Enum.join([type, query | rest], " ")}
    end
  end

  defp get_search_module(type) do
    case Map.get(@search_modules, type) do
      nil ->
        available = Map.keys(@search_modules) |> Enum.join(", ")
        Mix.raise("Invalid search type: #{type}. Available types: #{available}")
      
      module ->
        module
    end
  end

  defp check_api_key("brave") do
    unless Mulberry.config(:brave_api_key) do
      Mix.raise("BRAVE_API_KEY environment variable is required for Brave search")
    end
  end

  defp check_api_key("reddit") do
    unless Mulberry.config(:scrapecreators_api_key) do
      Mix.raise("SCRAPECREATORS_API_KEY environment variable is required for Reddit search")
    end
  end

  defp validate_options(opts, type) do
    opts = validate_format(opts)
    opts = validate_limit(opts)
    opts = validate_reddit_options(opts, type)
    opts
  end

  defp validate_format(opts) do
    case opts[:format] do
      nil -> Keyword.put(opts, :format, "text")
      format when format in ["text", "json", "markdown"] -> opts
      format ->
        Mix.raise("Invalid format: #{format}. Must be text, json, or markdown")
    end
  end

  defp validate_limit(opts) do
    case opts[:limit] do
      nil -> Keyword.put(opts, :limit, 10)
      limit when limit > 0 -> opts
      limit ->
        Mix.raise("Invalid limit: #{limit}. Must be greater than 0")
    end
  end

  defp validate_reddit_options(opts, "reddit") do
    opts = case opts[:sort] do
      nil -> opts
      sort when sort in ["relevance", "hot", "top", "new", "comments"] -> opts
      sort ->
        Mix.raise("Invalid sort: #{sort}. Must be relevance, hot, top, new, or comments")
    end

    case opts[:timeframe] do
      nil -> opts
      timeframe when timeframe in ["all", "year", "month", "week", "day", "hour"] -> opts
      timeframe ->
        Mix.raise("Invalid timeframe: #{timeframe}. Must be all, year, month, week, day, or hour")
    end
  end
  defp validate_reddit_options(opts, _), do: opts

  defp perform_search(Mulberry.Search.Brave, query, opts) do
    result_filter = opts[:result_filter] || "query,web"
    
    case Mulberry.Search.Brave.search(query, opts[:limit], result_filter) do
      {:ok, %Mulberry.Retriever.Response{content: content}} -> 
        Mulberry.Search.Brave.to_documents(content)
      {:ok, response} -> 
        Mulberry.Search.Brave.to_documents(response)
      error -> 
        error
    end
  end

  defp perform_search(Mulberry.Search.Reddit, query, opts) do
    # Build Reddit-specific options
    reddit_opts = []
    reddit_opts = maybe_add_option(reddit_opts, :sort, opts[:sort])
    reddit_opts = maybe_add_option(reddit_opts, :timeframe, opts[:timeframe])
    reddit_opts = maybe_add_option(reddit_opts, :after, opts[:after])
    reddit_opts = maybe_add_option(reddit_opts, :trim, opts[:trim])
    
    # Add subreddit to query if specified
    query = if subreddit = opts[:subreddit] do
      "subreddit:#{subreddit} #{query}"
    else
      query
    end
    
    case Mulberry.Search.Reddit.search(query, opts[:limit], reddit_opts) do
      {:ok, %Mulberry.Retriever.Response{content: content}} -> 
        Mulberry.Search.Reddit.to_documents(content)
      {:ok, response} -> 
        Mulberry.Search.Reddit.to_documents(response)
      error -> 
        error
    end
  end

  defp maybe_add_option(list, _key, nil), do: list
  defp maybe_add_option(list, key, value), do: Keyword.put(list, key, value)

  defp handle_success(documents, opts, type) do
    # Format the output
    output = case opts[:format] do
      "json" -> format_json(documents)
      "markdown" -> format_markdown(documents, type)
      _ -> format_text(documents, type)
    end
    
    # Save or display
    if save_path = opts[:save] do
      save_results(output, save_path, opts[:format])
    else
      display_results(output)
    end
    
    unless opts[:save] do
      Mix.shell().info("")
      Mix.shell().info("Found #{length(documents)} results")
    end
  end

  defp format_text([], _type) do
    "No results found."
  end

  defp format_text(documents, "reddit") do
    documents
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {doc, index} ->
      score = doc.meta[:score] || 0
      author = doc.meta[:author] || "unknown"
      subreddit = doc.meta[:subreddit] || "unknown"
      comments = doc.meta[:num_comments] || 0
      
      """
      #{index}. #{doc.title}
      ───────────────────────────────────────────────────────────────────────────────
      📍 r/#{subreddit} | 👤 #{author} | ⬆️ #{score} | 💬 #{comments}
      #{format_description(doc.description)}
      🔗 #{doc.url}
      """
    end)
  end

  defp format_text(documents, _type) do
    documents
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {doc, index} ->
      """
      #{index}. #{doc.title || "Untitled"}
      ───────────────────────────────────────────────────────────────────────────────
      #{format_description(doc.description)}
      🔗 #{doc.url}
      """
    end)
  end

  defp format_description(nil), do: "(No description)"
  defp format_description(""), do: "(No description)"
  defp format_description(desc) when byte_size(desc) > 200 do
    String.slice(desc, 0, 200) <> "..."
  end
  defp format_description(desc), do: desc

  defp format_markdown([], _type) do
    "# Search Results\n\nNo results found."
  end

  defp format_markdown(documents, "reddit") do
    header = "# Reddit Search Results\n\n"
    
    results = documents
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {doc, index} ->
      meta = format_reddit_metadata(doc.meta)
      
      """
      ## #{index}. #{doc.title}
      
      #{meta}
      
      #{doc.description || "_No description_"}
      
      **[View on Reddit](#{doc.url})**
      """
    end)
    
    header <> results
  end

  defp format_markdown(documents, _type) do
    header = "# Search Results\n\n"
    
    results = documents
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {doc, index} ->
      """
      ## #{index}. [#{doc.title || "Untitled"}](#{doc.url})
      
      #{doc.description || "_No description_"}
      """
    end)
    
    header <> results
  end

  defp format_reddit_metadata(meta) do
    """
    | Subreddit | Author | Score | Comments | Created |
    |-----------|--------|-------|----------|---------|
    | r/#{meta[:subreddit]} | u/#{meta[:author]} | #{meta[:score]} | #{meta[:num_comments]} | #{format_timestamp(meta[:created_at_iso])} |
    """
  end

  defp format_timestamp(nil), do: "N/A"
  defp format_timestamp(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, datetime, _} ->
        Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
      _ ->
        "N/A"
    end
  end

  defp format_json(documents) do
    documents
    |> Enum.map(&Map.from_struct/1)
    |> Jason.encode!(pretty: true)
  end

  defp save_results(content, path, format) do
    case File.write(path, content) do
      :ok ->
        Mix.shell().info("")
        Mix.shell().info("Results saved to: #{path}")
        Mix.shell().info("Format: #{format}")
        Mix.shell().info("Size: #{byte_size(content)} bytes")
        
      {:error, reason} ->
        Mix.shell().error("Failed to save file: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp display_results(output) do
    Mix.shell().info("")
    Mix.shell().info(output)
  end
end