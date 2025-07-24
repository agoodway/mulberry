defmodule Mulberry.Research.Web do
  @moduledoc """
  Web-based research implementation using search engines and online sources.

  This module implements the Research.Behaviour for conducting research
  using web searches and online content retrieval.
  """

  @behaviour Mulberry.Research.Behaviour

  require Logger

  alias Mulberry.Research.{Chain, Result}
  alias Mulberry.Document
  alias Mulberry.Document.WebPage
  alias LangChain.Chains.LLMChain
  alias LangChain.PromptTemplate
  alias LangChain.Utils.ChainResult

  @doc """
  Conducts web-based research on a topic.
  """
  @impl true
  @spec research(String.t(), Chain.t(), Keyword.t()) :: {:ok, Result.t()} | {:error, term()}
  def research(topic, %Chain{} = chain, opts \\ []) do
    opts_with_topic = Keyword.put(opts, :topic, topic)
    with {:ok, sources} <- gather_sources(topic, chain, opts),
         _ <- maybe_call_progress(opts, :sources_gathered, %{count: length(sources)}),
         {:ok, analysis} <- analyze_sources(sources, chain, opts_with_topic),
         _ <- maybe_call_progress(opts, :analysis_complete, %{sources_analyzed: length(sources)}) do
      synthesize_findings(analysis, chain, opts_with_topic)
    end
  end

  @doc """
  Gathers web sources for the research topic.
  """
  @impl true
  @spec gather_sources(String.t(), Chain.t(), Keyword.t()) :: {:ok, [Document.t()]} | {:error, term()}
  def gather_sources(topic, %Chain{} = chain, opts \\ []) do
    with {:ok, search_queries} <- generate_search_queries(topic, chain),
         _ <- maybe_log(chain, "Generated search queries: #{inspect(search_queries)}"),
         opts_with_topic = Keyword.put(opts, :topic, topic),
         {:ok, search_results} <- perform_searches(search_queries, chain, opts_with_topic),
         _ <- maybe_log(chain, "Found #{length(search_results)} search results"),
         {:ok, documents} <- fetch_documents(search_results, chain, opts_with_topic) do
      
      # Filter documents but don't limit to max_sources yet
      # We'll try more sources if some fail during analysis
      filtered_docs = filter_documents(documents, chain)
      
      _ = maybe_call_progress(opts, :documents_selected, %{
        total_found: length(documents),
        selected: length(filtered_docs)
      })
      
      {:ok, filtered_docs}
    end
  end

  @doc """
  Analyzes gathered web sources.
  """
  @impl true
  @spec analyze_sources([Document.t()], Chain.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
  def analyze_sources(sources, %Chain{} = chain, opts \\ []) do
    topic = Keyword.get(opts, :topic, "research")
    max_sources = chain.max_sources
    
    # Try to analyze sources until we have enough successful analyses
    analyses = sources
      |> analyze_sources_until_max(chain, topic, opts, max_sources)
      |> Map.new()
    
    {:ok, %{
      source_analyses: analyses,
      source_count: length(sources),
      analyzed_count: map_size(analyses)
    }}
  end
  
  defp analyze_sources_until_max(sources, chain, topic, opts, max_needed) do
    sources
    |> Enum.with_index()
    |> Enum.reduce_while([], fn {source, index}, acc ->
      if length(acc) >= max_needed do
        {:halt, acc}
      else
        _ = maybe_call_progress(opts, :analyzing_source, %{
          current: index + 1,
          total: length(sources)
        })
        
        handle_source_analysis(source, chain, topic, opts, acc)
      end
    end)
    |> Enum.reverse()
  end
  
  defp handle_source_analysis(source, chain, topic, _opts, acc) do
    case analyze_single_source(source, chain, topic) do
      {:ok, analysis} -> 
        {:cont, [{source, analysis} | acc]}
      {:error, reason} -> 
        _ = maybe_log(chain, "Failed to analyze source: #{inspect(reason)}")
        {:cont, acc}
    end
  end

  @doc """
  Synthesizes findings from web source analysis.
  """
  @impl true
  @spec synthesize_findings(map(), Chain.t(), Keyword.t()) :: {:ok, Result.t()} | {:error, term()}
  def synthesize_findings(%{source_analyses: analyses} = analysis_data, %Chain{} = chain, opts) do
    topic = Keyword.get(opts, :topic, "research")
    
    with {:ok, synthesis} <- generate_synthesis(analyses, topic, chain),
         {:ok, findings} <- extract_findings(synthesis, topic, chain),
         {:ok, detailed_content} <- generate_detailed_content(analyses, topic, chain),
         {:ok, stats} <- extract_content_stats(analyses, topic, chain),
         sources <- Map.keys(analyses) do
      
      
      result = %{
        topic: topic,
        summary: synthesis.summary,
        detailed_content: detailed_content,
        sources: sources,
        key_findings: findings,
        themes: synthesis.themes,
        related_topics: synthesis.related_topics,
        metadata: %{
          strategy: :web,
          sources_analyzed: analysis_data.analyzed_count,
          timestamp: DateTime.utc_now()
        },
        stats: stats
      }
      
      result
      |> Result.new!()
      |> Result.calculate_confidence()
      |> then(&{:ok, &1})
    end
  end

  # Private functions

  defp generate_search_queries(topic, %Chain{} = chain) do
    # Generate queries based on max_sources to ensure we have enough
    num_queries = max(chain.max_sources, 3)  # At least 3 queries
    
    prompt = """
    Generate exactly <%= @num_queries %> diverse search queries for researching the topic: <%= @topic %>
    
    Each query should:
    - Target different aspects of the topic
    - Be specific enough to return relevant results
    - Not be too narrow that it returns no results
    
    Output one query per line, no numbering or bullets.
    """
    
    messages =
      [
        PromptTemplate.new!(%{
          role: :user,
          text: prompt
        })
      ]
      |> PromptTemplate.to_messages!(%{topic: topic, num_queries: num_queries})
    
    case run_llm(chain, messages) do
      {:ok, response} ->
        queries =
          response
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.take(num_queries)
        
        # If we don't have enough queries, add fallback queries
        queries = ensure_enough_queries(queries, topic, num_queries)
        
        {:ok, queries}
      
      error -> error
    end
  end
  
  defp ensure_enough_queries(queries, topic, needed) when length(queries) < needed do
    fallback_queries = [
      "#{topic} overview",
      "#{topic} benefits advantages",
      "#{topic} challenges disadvantages",
      "#{topic} current trends",
      "#{topic} future outlook",
      "#{topic} case studies examples",
      "#{topic} implementation guide"
    ]
    
    additional_needed = needed - length(queries)
    queries ++ Enum.take(fallback_queries, additional_needed)
  end
  defp ensure_enough_queries(queries, _topic, _needed), do: queries

  defp perform_searches(queries, %Chain{} = chain, opts) do
    search_modules = Chain.get_search_modules(chain)
    max_sources = chain.max_sources
    
    # Perform parallel searches across all modules
    results = 
      search_modules
      |> Task.async_stream(
        fn module_config ->
          perform_module_searches(queries, module_config, chain, opts)
        end,
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, module_results} -> module_results
        {:exit, :timeout} -> 
          maybe_log(chain, "Search module timed out")
          []
        _ -> []
      end)
      |> deduplicate_and_rank(search_modules)
    
    # Ensure we have at least max_sources results
    if length(results) < max_sources do
      # Try broader searches if we don't have enough
      additional_results = perform_fallback_searches_multi(
        search_modules,
        max_sources - length(results),
        chain,
        opts
      )
      
      all_results = (results ++ additional_results) |> deduplicate_and_rank(search_modules)
      {:ok, Enum.take(all_results, max_sources * 2)} # Take more than needed for filtering
    else
      {:ok, results}
    end
  end
  

  defp fetch_documents(search_results, %Chain{} = _chain, opts) do
    documents =
      search_results
      |> Enum.map(fn result ->
        _ = maybe_call_progress(opts, :fetching_document, %{url: result.url})
        
        # Keep the search result as-is, which already contains title, description, and url
        result
      end)
      |> Enum.reject(&is_nil/1)
    
    {:ok, documents}
  end

  defp filter_documents(documents, %Chain{} = _chain) do
    Enum.filter(documents, &valid_document?/1)
  end
  
  defp valid_document?(%WebPage{url: url}) when is_binary(url), do: true
  defp valid_document?(doc) do
    case Document.to_text(doc) do
      {:ok, text} -> String.length(text) > 100
      _ -> false
    end
  end

  defp analyze_single_source(source, %Chain{} = chain, topic) do
    # For web search results, use title and description as content
    content = case source do
      %WebPage{title: title, description: description, url: url} ->
        text_content = [
          if(title, do: "Title: #{title}", else: nil),
          if(description, do: "Description: #{description}", else: nil),
          if(url, do: "URL: #{url}", else: nil)
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n\n")
        
        if String.length(text_content) > 10 do
          {:ok, text_content}
        else
          {:error, :insufficient_content}
        end
        
      _ ->
        Document.to_text(source)
    end
    
    with {:ok, text} <- content do
      # For search results, use the text as-is (no chunking needed)
      analysis_text = text
      
      prompt = Chain.get_source_analysis_prompt(chain)
      
      messages =
        [
          PromptTemplate.new!(%{
            role: :user,
            text: prompt
          })
        ]
        |> PromptTemplate.to_messages!(%{
          topic: topic,
          content: analysis_text
        })
      
      run_llm(chain, messages)
    end
  end

  defp generate_synthesis(analyses, topic, %Chain{} = chain) do
    # Format analyses for synthesis
    analyses_text =
      analyses
      |> Enum.map_join("\n\n---\n\n", fn {source, analysis} ->
        title = get_source_identifier(source)
        "Source: #{title}\n#{analysis}"
      end)
    
    prompt = Chain.get_synthesis_prompt(chain)
    
    messages =
      [
        PromptTemplate.new!(%{
          role: :user,
          text: prompt
        })
      ]
      |> PromptTemplate.to_messages!(%{
        topic: topic,
        analyses: analyses_text
      })
    
    case run_llm(chain, messages) do
      {:ok, response} ->
        # Parse the synthesis response
        {:ok, parse_synthesis_response(response)}
      
      error -> error
    end
  end

  defp extract_findings(synthesis, topic, %Chain{} = chain) do
    prompt = Chain.get_finding_extraction_prompt(chain)
    
    messages =
      [
        PromptTemplate.new!(%{
          role: :user,
          text: prompt
        })
      ]
      |> PromptTemplate.to_messages!(%{
        topic: topic,
        analysis: synthesis.summary
      })
    
    case run_llm(chain, messages) do
      {:ok, response} ->
        findings = parse_findings_response(response)
        {:ok, findings}
      
      error -> error
    end
  end

  defp parse_synthesis_response(response) do
    # Simple parsing - could be enhanced with structured output
    sections = String.split(response, ~r/\n{2,}/)
    
    %{
      summary: Enum.at(sections, 0, response),
      themes: extract_list_section(response, "themes"),
      related_topics: extract_list_section(response, "related|further research")
    }
  end

  defp parse_findings_response(response) do
    # Parse the structured findings from the LLM response
    # Look for patterns like "Finding:" or bullet points followed by finding text
    findings = response
    |> String.split(~r/(?:Finding:|^\d+\.|^[-*•])\s*/m)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.length(&1) < 10))
    |> Enum.map(&parse_single_finding/1)
    |> Enum.reject(&is_nil/1)
    
    # If no structured findings found, try to extract from paragraphs
    if Enum.empty?(findings) do
      response
      |> String.split(~r/\n\n+/)
      |> Enum.take(5)  # Limit to first 5 paragraphs
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.length(&1) < 20))
      |> Enum.map(fn text ->
        %{
          text: clean_finding_text(text),
          source_ids: [],
          confidence: 0.7
        }
      end)
    else
      findings
    end
  end
  
  defp parse_single_finding(text) do
    # Try to extract structured finding with evidence and confidence
    if String.contains?(text, ["Evidence:", "Supporting evidence:", "Source:", "Confidence:"]) do
      parse_structured_finding(text)
    else
      # Simple finding text
      %{
        text: clean_finding_text(text),
        source_ids: [],
        confidence: 0.8
      }
    end
  end
  
  defp parse_structured_finding(text) do
    lines = String.split(text, "\n")
    finding_text = hd(lines) |> clean_finding_text()
    
    _evidence = extract_field(text, ~r/(?:Supporting evidence|Evidence):\s*(.+?)(?:\n|$)/i)
    _source = extract_field(text, ~r/Source.*?:\s*(.+?)(?:\n|$)/i)
    confidence_str = extract_field(text, ~r/Confidence.*?:\s*(\d+\.?\d*|\d+%)/i)
    
    confidence = parse_confidence(confidence_str)
    
    %{
      text: finding_text,
      source_ids: [],
      confidence: confidence
    }
  end
  
  defp extract_field(text, regex) do
    case Regex.run(regex, text) do
      [_, match] -> String.trim(match)
      _ -> nil
    end
  end
  
  defp parse_confidence(nil), do: 0.8
  defp parse_confidence(str) do
    str
    |> String.replace("%", "")
    |> Float.parse()
    |> case do
      {num, _} when num > 1 -> num / 100.0
      {num, _} -> num
      _ -> 0.8
    end
  end

  defp extract_list_section(text, pattern) do
    regex = ~r/#{pattern}[:\s]*\n((?:[-*•].+\n?)+)/i
    
    case Regex.run(regex, text) do
      [_, section] ->
        section
        |> String.split(~r/\n[-*•]/)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
      
      _ -> []
    end
  end
  
  defp generate_detailed_content(analyses, topic, %Chain{} = chain) do
    content_length = chain.content_length
    word_count = get_word_count_for_length(content_length)
    
    # Format source information for the LLM
    source_content = analyses
    |> Enum.map_join("\n\n---\n\n", fn {source, analysis} ->
      title = get_source_identifier(source)
      "Source: #{title}\nAnalysis: #{analysis}"
    end)
    
    prompt = """
    You are creating a detailed, informative article about the research topic.
    Use the provided source analyses to create comprehensive content.
    
    Topic: <%= @topic %>
    Target length: <%= @word_count %> words (#{content_length})
    
    Source analyses:
    <%= @source_content %>
    
    Create a well-structured, detailed article that:
    1. Provides comprehensive coverage of the topic
    2. Integrates information from all sources
    3. Uses clear headings and sections
    4. Includes specific examples and data where available
    5. Maintains an informative, neutral tone
    
    The content should be educational and thorough, suitable for someone
    wanting to understand the topic in depth.
    """
    
    messages =
      [
        PromptTemplate.new!(%{
          role: :user,
          text: prompt
        })
      ]
      |> PromptTemplate.to_messages!(%{
        topic: topic,
        word_count: word_count,
        source_content: source_content
      })
    
    case run_llm(chain, messages) do
      {:ok, content} -> {:ok, content}
      error -> error
    end
  end
  
  defp get_word_count_for_length("short"), do: 300
  defp get_word_count_for_length("medium"), do: 800
  defp get_word_count_for_length("long"), do: 1500
  defp get_word_count_for_length("comprehensive"), do: 2500
  defp get_word_count_for_length(_), do: 800  # default to medium
  
  defp extract_content_stats(analyses, topic, %Chain{} = chain) do
    # Combine all analyses into one text for statistics extraction
    combined_analyses = analyses
    |> Enum.map_join("\n\n", fn {_source, analysis} -> analysis end)
    
    prompt = """
    Analyze the following research content about <%= @topic %> and extract key statistics, numbers, dates, percentages, and quantitative information.
    
    Content to analyze:
    <%= @content %>
    
    Extract statistics and format them in this exact structure:
    
    **Key Numbers & Percentages:**
    - [value]: [context]
    - [value]: [context]
    
    **Dates & Timelines:**
    - [date/year]: [what happened or will happen]
    - [date/year]: [what happened or will happen]
    
    **Financial Data:**
    - [amount]: [context]
    - [amount]: [context]
    
    **Comparisons & Rankings:**
    - [comparison]: [context]
    - [comparison]: [context]
    
    **Quantities & Measurements:**
    - [quantity]: [context]
    - [quantity]: [context]
    
    Only include categories where you find actual data. For each statistic:
    - Use the exact number/percentage/date from the source
    - Provide brief, clear context
    - Do not include vague or estimated values
    - If a source is mentioned, include it in parentheses at the end
    
    Example format:
    - 2.7x: Global renewable capacity growth by 2030 (IEA)
    - 90%: Utility-scale solar and wind share of new capacity (Deloitte)
    """
    
    messages =
      [
        PromptTemplate.new!(%{
          role: :user,
          text: prompt
        })
      ]
      |> PromptTemplate.to_messages!(%{
        topic: topic,
        content: combined_analyses
      })
    
    case run_llm(chain, messages) do
      {:ok, response} ->
        {:ok, parse_stats_response(response)}
      
      error -> error
    end
  end
  
  defp parse_stats_response(response) do
    # Parse the LLM response into structured categories
    stats = %{
      numbers_and_percentages: extract_formatted_stats(response, "Key Numbers & Percentages"),
      dates_and_timelines: extract_formatted_stats(response, "Dates & Timelines"),
      financial: extract_formatted_stats(response, "Financial Data"),
      comparisons: extract_formatted_stats(response, "Comparisons & Rankings"),
      quantities: extract_formatted_stats(response, "Quantities & Measurements")
    }
    
    # Remove empty categories
    stats
    |> Enum.reject(fn {_key, value} -> 
      is_nil(value) or (is_list(value) and Enum.empty?(value))
    end)
    |> Map.new()
  end
  
  defp extract_formatted_stats(text, category_name) do
    # Extract stats from a formatted section like:
    # **Category Name:**
    # - value: context
    # - value: context
    
    section_pattern = ~r/\*\*#{Regex.escape(category_name)}:\*\*\s*\n((?:[-•]\s*.+(?:\n|$))+)/m
    
    case Regex.run(section_pattern, text) do
      [_, section] ->
        section
        |> String.split(~r/\n/)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.filter(&String.starts_with?(&1, ["-", "•"]))
        |> Enum.map(&String.replace(&1, ~r/^[-•]\s*/, ""))
        |> Enum.map(&parse_formatted_stat/1)
        |> Enum.reject(&is_nil/1)
      
      _ -> []
    end
  end
  
  defp parse_formatted_stat(text) do
    # Parse stats in format "value: context" or "value: context (source)"
    case String.split(text, ":", parts: 2) do
      [value, context] ->
        %{
          value: String.trim(value),
          context: String.trim(context),
          full_text: text
        }
      
      _ -> nil
    end
  end

  defp clean_finding_text(text) do
    text
    |> String.replace(~r/^[-*•]\s*/, "")
    |> String.replace(~r/\(confidence:.*\)$/i, "")
    |> String.trim()
  end

  defp get_source_identifier(%WebPage{url: url}), do: url
  defp get_source_identifier(%{title: title}) when is_binary(title), do: title
  defp get_source_identifier(%{url: url}) when is_binary(url), do: url
  defp get_source_identifier(_), do: "Unknown source"

  defp run_llm(%Chain{llm: llm, verbose: verbose}, messages) do
    %{llm: llm, verbose: verbose}
    |> LLMChain.new!()
    |> LLMChain.add_messages(messages)
    |> LLMChain.run()
    |> ChainResult.to_string()
  end

  
  defp perform_module_searches(queries, module_config, chain, _opts) do
    %{module: search_module, options: module_options, weight: weight} = module_config
    
    # Calculate results per query for this module
    results_per_query = max(div(chain.max_sources * 2, length(queries)), 1)
    
    # Merge module-specific options with chain search options
    # First merge chain options, then module options (module options take precedence)
    search_opts = chain.search_options
    |> Map.merge(%{
      include_domains: chain.include_domains,
      exclude_domains: chain.exclude_domains
    })
    |> Map.merge(module_options)
    |> Enum.into([])
    
    # Perform searches and add module metadata
    queries
    |> Enum.flat_map(fn query ->
      search_and_convert_with_metadata(search_module, query, results_per_query, search_opts, weight)
    end)
  end
  
  defp search_and_convert_with_metadata(search_module, query, max_sources, search_opts, weight) do
    case apply(search_module, :search, [query, max_sources, search_opts]) do
      {:ok, %Mulberry.Retriever.Response{status: :ok, content: content}} -> 
        convert_and_add_metadata(search_module, content, weight)
      {:ok, content} when is_map(content) ->
        convert_and_add_metadata(search_module, content, weight)
      {:error, _} -> []
      _ -> []
    end
  end
  
  defp convert_and_add_metadata(search_module, content, weight) do
    case search_module.to_documents(content) do
      {:ok, docs} -> 
        add_search_metadata(docs, search_module, weight)
      _ -> []
    end
  end
  
  defp add_search_metadata(docs, search_module, weight) do
    Enum.map(docs, fn doc ->
      updated_meta = (doc.meta || []) ++ [
        search_module: search_module,
        search_weight: weight
      ]
      %{doc | meta: updated_meta}
    end)
  end
  
  defp deduplicate_and_rank(results, _search_modules) do
    # Group by URL, keeping the highest weighted version
    results
    |> Enum.group_by(& &1.url)
    |> Enum.map(fn {_url, docs} ->
      # Keep the document with highest weight
      Enum.max_by(docs, fn doc ->
        Keyword.get(doc.meta || [], :search_weight, 1.0)
      end)
    end)
    |> Enum.sort_by(fn doc ->
      # Sort by weight (descending)
      weight = Keyword.get(doc.meta || [], :search_weight, 1.0)
      -weight
    end)
  end
  
  defp perform_fallback_searches_multi(search_modules, needed, chain, opts) do
    topic = Keyword.get(opts, :topic, "research")
    
    search_modules
    |> Enum.take(2) # Use first 2 modules for fallback
    |> Enum.flat_map(fn module_config ->
      perform_module_searches([topic], module_config, chain, opts)
    end)
    |> Enum.take(needed)
  end


  defp maybe_log(%Chain{verbose: true}, message), do: Logger.info(message)
  defp maybe_log(_, _), do: :ok

  defp maybe_call_progress(opts, stage, info) do
    case Keyword.get(opts, :on_progress) do
      nil -> :ok
      callback when is_function(callback, 2) -> callback.(stage, info)
      _ -> :ok
    end
  end
end
