defmodule Mix.Tasks.Text do
  @moduledoc """
  Performs text processing operations using Mulberry.Text module.

  This task provides access to various text analysis and transformation
  capabilities including summarization, title generation, and classification.

  ## Usage

      mix text OPERATION [OPTIONS]

  ## Operations

    * `summarize` - Generate a summary of the provided text
    * `title` - Generate a concise title for the text
    * `classify` - Classify text into one of the provided categories
    * `split` - Split text into semantic chunks
    * `tokens` - Tokenize text and optionally count tokens

  ## Options

    * `--text` - Text to process (required for most operations)
    * `--file` - Read text from a file instead of --text
    * `--provider` - LLM provider (openai, anthropic, google, etc.)
    * `--model` - Model to use for the provider
    * `--temperature` - Temperature setting (0.0-1.0)
    * `--categories` - Comma-separated list of categories (for classify)
    * `--examples` - JSON array of {text, category} examples (for classify)
    * `--fallback-category` - Fallback category if classification fails
    * `--fallback-title` - Fallback title if generation fails
    * `--max-words` - Maximum words in title (default: 14)
    * `--strategy` - Summarization strategy (stuff, map_reduce, refine)
    * `--chunk-size` - Chunk size for splitting (default: 1000)
    * `--verbose` - Enable verbose output
    * `--output` - Output format (text, json)
    * `--save` - Save output to file

  ## Examples

      # Summarize text
      mix text summarize --text "Long article text..."
      
      # Summarize from file with specific provider
      mix text summarize --file article.txt --provider anthropic
      
      # Generate title with custom max words
      mix text title --text "Article content..." --max-words 10
      
      # Classify text with categories
      mix text classify --text "Tech news..." --categories "Technology,Business,Health"
      
      # Classify with examples and fallback
      mix text classify --file news.txt --categories "Tech,Business" \\
        --examples '[{"text":"iPhone release","category":"Tech"}]' \\
        --fallback-category "Other"
      
      # Split text into chunks
      mix text split --file document.txt --chunk-size 500
      
      # Count tokens
      mix text tokens --text "Sample text to tokenize" --output json
  """

  use Mix.Task
  import Mix.Shell.IO

  @shortdoc "Performs text processing operations"

  @impl Mix.Task
  def run(args) do
    {opts, [operation | _], _} = parse_args(args)
    
    # Start the application
    Mix.Task.run("app.start")
    
    # Get text input
    text = get_text_input(opts)
    
    # Execute the requested operation
    case operation do
      "summarize" -> handle_summarize(text, opts)
      "title" -> handle_title(text, opts)
      "classify" -> handle_classify(text, opts)
      "split" -> handle_split(text, opts)
      "tokens" -> handle_tokens(text, opts)
      _ -> raise_error("Unknown operation: #{operation}. Use summarize, title, classify, split, or tokens.")
    end
  rescue
    e ->
      raise_error("Error: #{Exception.message(e)}")
  end

  defp parse_args(args) do
    OptionParser.parse(args,
      strict: [
        text: :string,
        file: :string,
        provider: :string,
        model: :string,
        temperature: :float,
        categories: :string,
        examples: :string,
        fallback_category: :string,
        fallback_title: :string,
        max_words: :integer,
        strategy: :string,
        chunk_size: :integer,
        verbose: :boolean,
        output: :string,
        save: :string
      ],
      aliases: [
        t: :text,
        f: :file,
        p: :provider,
        m: :model,
        c: :categories,
        v: :verbose,
        o: :output,
        s: :save
      ]
    )
  end

  defp get_text_input(opts) do
    cond do
      opts[:text] -> opts[:text]
      opts[:file] -> File.read!(opts[:file])
      true -> raise_error("You must provide either --text or --file")
    end
  end

  defp handle_summarize(text, opts) do
    info("Generating summary...")
    
    summary_opts = build_llm_opts(opts)
    |> maybe_add_option(:strategy, opts[:strategy], &String.to_atom/1)
    |> maybe_add_option(:chunk_size, opts[:chunk_size])
    |> maybe_add_option(:verbose, opts[:verbose])
    
    case Mulberry.Text.summarize(text, summary_opts) do
      {:ok, summary} ->
        output_result("Summary", summary, opts)
      {:error, reason} ->
        raise_error("Failed to generate summary: #{inspect(reason)}")
    end
  end

  defp handle_title(text, opts) do
    info("Generating title...")
    
    title_opts = build_llm_opts(opts)
    |> maybe_add_option(:max_words, opts[:max_words])
    |> maybe_add_option(:fallback_title, opts[:fallback_title])
    |> maybe_add_option(:verbose, opts[:verbose])
    
    case Mulberry.Text.title(text, title_opts) do
      {:ok, title} ->
        output_result("Title", title, opts)
      {:error, reason} ->
        raise_error("Failed to generate title: #{inspect(reason)}")
    end
  end

  defp handle_classify(text, opts) do
    unless opts[:categories] do
      raise_error("You must provide --categories for classification")
    end
    
    categories = String.split(opts[:categories], ",", trim: true)
    info("Classifying into categories: #{inspect(categories)}")
    
    classify_opts = build_llm_opts(opts)
    |> Keyword.put(:categories, categories)
    |> maybe_add_option(:fallback_category, opts[:fallback_category])
    |> maybe_add_option(:verbose, opts[:verbose])
    
    # Parse examples if provided
    classify_opts = if opts[:examples] do
      parse_examples(opts[:examples], classify_opts)
    else
      classify_opts
    end
    
    case Mulberry.Text.classify(text, classify_opts) do
      {:ok, category} ->
        output_result("Category", category, opts)
      {:error, reason} ->
        raise_error("Failed to classify: #{inspect(reason)}")
    end
  end

  defp handle_split(text, opts) do
    info("Splitting text into chunks...")
    
    chunks = Mulberry.Text.split(text)
    
    if opts[:output] == "json" do
      output_json(%{
        operation: "split",
        chunk_count: length(chunks),
        chunks: Enum.with_index(chunks, fn chunk, idx ->
          %{
            index: idx,
            text: chunk,
            length: String.length(chunk)
          }
        end)
      }, opts)
    else
      info("Text split into #{length(chunks)} chunks:\n")
      
      Enum.each(Enum.with_index(chunks), fn {chunk, idx} ->
        info("--- Chunk #{idx + 1} (#{String.length(chunk)} chars) ---")
        info(chunk)
        info("")
      end)
      
      maybe_save_output(Enum.join(chunks, "\n\n---\n\n"), opts)
    end
  end

  defp handle_tokens(text, opts) do
    info("Tokenizing text...")
    
    case Mulberry.Text.tokens(text) do
      {:ok, tokens} ->
        handle_tokens_success(tokens, opts)
        
      {:error, reason} ->
        raise_error("Failed to tokenize: #{inspect(reason)}")
    end
  end
  
  defp handle_tokens_success(tokens, opts) do
    token_count = length(tokens)
    
    if opts[:output] == "json" do
      output_json(%{
        operation: "tokens",
        token_count: token_count,
        tokens: tokens
      }, opts)
    else
      info("Token count: #{token_count}")
      
      if opts[:verbose] do
        info("\nTokens:")
        info(inspect(tokens, pretty: true, width: 80))
      end
      
      maybe_save_output("Token count: #{token_count}\n\nTokens:\n#{inspect(tokens, pretty: true)}", opts)
    end
  end

  defp parse_examples(examples_json, classify_opts) do
    case Jason.decode(examples_json) do
      {:ok, examples} ->
        parsed_examples = Enum.map(examples, fn example ->
          parse_single_example(example)
        end)
        Keyword.put(classify_opts, :examples, parsed_examples)
      {:error, _} ->
        raise_error("Invalid JSON in --examples")
    end
  end
  
  defp parse_single_example(%{"text" => text, "category" => category}) do
    {text, category}
  end
  
  defp parse_single_example(_) do
    raise_error("Invalid example format. Expected {\"text\": \"...\", \"category\": \"...\"}")
  end

  defp build_llm_opts(opts) do
    []
    |> maybe_add_option(:provider, opts[:provider], &String.to_atom/1)
    |> maybe_add_option(:model, opts[:model])
    |> maybe_add_option(:temperature, opts[:temperature])
  end

  defp maybe_add_option(keyword_list, _key, nil), do: keyword_list
  defp maybe_add_option(keyword_list, key, value), do: Keyword.put(keyword_list, key, value)
  defp maybe_add_option(keyword_list, _key, nil, _transform), do: keyword_list
  defp maybe_add_option(keyword_list, key, value, transform), do: Keyword.put(keyword_list, key, transform.(value))

  defp output_result(label, result, opts) do
    if opts[:output] == "json" do
      output_json(%{
        operation: String.downcase(label),
        result: result
      }, opts)
    else
      info("#{label}: #{result}")
      maybe_save_output(result, opts)
    end
  end

  defp output_json(data, opts) do
    json = Jason.encode!(data, pretty: true)
    info(json)
    maybe_save_output(json, opts)
  end

  defp maybe_save_output(content, opts) do
    if opts[:save] do
      File.write!(opts[:save], content)
      info("\nOutput saved to: #{opts[:save]}")
    end
  end

  defp raise_error(message) do
    Mix.raise(message)
  end
end