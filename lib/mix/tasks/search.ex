defmodule Mix.Tasks.Search do
  @moduledoc """
  Performs searches using various providers.

  ## Usage

      mix search [TYPE] QUERY [options]

  ## Search Types

    * `brave` - Web search using Brave Search API (default)
    * `google` - Google search using ScrapeCreators API
    * `reddit` - Reddit post search using ScrapeCreators API
    * `facebook_ads` - Facebook ads search using ScrapeCreators API
    * `facebook_ad_companies` - Facebook ad companies search using ScrapeCreators API
    * `google_ads` - Google ads search using ScrapeCreators API
    * `youtube` - YouTube search using ScrapeCreators API

  ## Common Options

    * `--limit` - Maximum number of results (default: 10)
    * `--format` - Output format: text, json, or markdown (default: text)
    * `--save` - Save results to specified file
    * `--verbose` - Show detailed information

  ## Provider-Specific Options

  ### Brave Search

    * `--result-filter` - Filter results, e.g., "query,web" (default: "query,web")

  ### Google Search

    * `--region` - 2 letter country code, e.g., US, UK, CA (optional)

  ### Reddit Search

    * `--sort` - Sort order: relevance, hot, top, new, comments
    * `--timeframe` - Time filter: all, year, month, week, day, hour
    * `--subreddit` - Filter by specific subreddit
    * `--after` - Pagination token for next page
    * `--trim` - Get trimmed responses (boolean)

  ### Facebook Ads Search

    * `--search-by` - Search by: company_name (default) or page_id
    * `--country` - 2-letter country code (e.g., US, GB)
    * `--status` - Ad status: ACTIVE (default), INACTIVE, or ALL
    * `--media-type` - Media type: ALL (default), image, video, or meme
    * `--cursor` - Pagination cursor for next page
    * `--trim` - Get trimmed responses (boolean)

  ### Facebook Ad Companies Search

    * `--cursor` - Pagination cursor for next page

  ### Google Ads Search

    * `--advertiser-id` - Search by advertiser ID instead of domain
    * `--topic` - Topic filter: political, etc. (requires --region for political)
    * `--region` - Region filter (e.g., US, UK, CA)
    * `--cursor` - Pagination cursor for next page

  ### YouTube Search

    * `--upload-date` - Upload date filter: lastHour, today, thisWeek, thisMonth, thisYear
    * `--sort-by` - Sort order: relevance, uploadDate, viewCount, rating
    * `--filter` - Filter by type: video, channel, playlist
    * `--continuation-token` - Pagination token for next page

  ## Examples

      # Default Brave search
      mix search "elixir programming"

      # Explicit Brave search
      mix search brave "phoenix framework"

      # Google search
      mix search google "machine learning"

      # Google search with region
      mix search google "local news" --region UK

      # Reddit search
      mix search reddit "machine learning"

      # Reddit search with options
      mix search reddit "elixir tips" --sort top --timeframe month

      # Save results as JSON
      mix search reddit "web scraping" --format json --save results.json

      # Filter by subreddit
      mix search reddit "tips" --subreddit elixir

      # YouTube search
      mix search youtube "elixir tutorial"

      # YouTube with filters
      mix search youtube "phoenix framework" --sort-by viewCount --upload-date thisMonth

      # Verbose mode with limit
      mix search brave "phoenix liveview" --verbose --limit 5

      # Facebook ads search by company name
      mix search facebook_ads "Nike"

      # Facebook ads search by page ID
      mix search facebook_ads "123456789" --search-by page_id

      # Facebook ads with filters
      mix search facebook_ads "Apple" --country US --status ACTIVE --media-type video

      # Facebook ad companies search
      mix search facebook_ad_companies "Nike"

      # Google ads search by domain
      mix search google_ads "nike.com"

      # Google ads search by advertiser ID
      mix search google_ads --advertiser-id "AR01614014350098432001"

      # Google ads search with filters
      mix search google_ads "example.com" --topic political --region US
  """

  use Mix.Task

  @shortdoc "Performs searches using various providers"

  @search_modules %{
    "brave" => Mulberry.Search.Brave,
    "google" => Mulberry.Search.Google,
    "reddit" => Mulberry.Search.Reddit,
    "facebook_ads" => Mulberry.Search.FacebookAds,
    "facebook_ad_companies" => Mulberry.Search.FacebookAdCompanies,
    "google_ads" => Mulberry.Search.GoogleAds,
    "youtube" => Mulberry.Search.YouTube
  }

  @impl Mix.Task
  def run(args) do
    {opts, args_list, _} =
      OptionParser.parse(args,
        switches: [
          limit: :integer,
          format: :string,
          save: :string,
          verbose: :boolean,
          result_filter: :string,
          region: :string,
          sort: :string,
          timeframe: :string,
          subreddit: :string,
          after: :string,
          trim: :boolean,
          search_by: :string,
          country: :string,
          status: :string,
          media_type: :string,
          cursor: :string,
          upload_date: :string,
          sort_by: :string,
          filter: :string,
          continuation_token: :string,
          advertiser_id: :string,
          topic: :string
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
        available = Map.keys(@search_modules) |> Enum.sort() |> Enum.join(", ")

        Mix.raise("""
        Invalid search type: '#{type}'

        Available search types:
          #{available}

        Usage: mix search [TYPE] QUERY [options]

        For more help: mix help search
        """)

      module ->
        module
    end
  end

  defp check_api_key("brave") do
    unless Mulberry.config(:brave_api_key) do
      Mix.raise("BRAVE_API_KEY environment variable is required for Brave search")
    end
  end

  defp check_api_key("google") do
    unless Mulberry.config(:scrapecreators_api_key) do
      Mix.raise("SCRAPECREATORS_API_KEY environment variable is required for Google search")
    end
  end

  defp check_api_key("reddit") do
    unless Mulberry.config(:scrapecreators_api_key) do
      Mix.raise("SCRAPECREATORS_API_KEY environment variable is required for Reddit search")
    end
  end

  defp check_api_key("facebook_ads") do
    unless Mulberry.config(:scrapecreators_api_key) do
      Mix.raise("SCRAPECREATORS_API_KEY environment variable is required for Facebook Ads search")
    end
  end

  defp check_api_key("youtube") do
    unless Mulberry.config(:scrapecreators_api_key) do
      Mix.raise("SCRAPECREATORS_API_KEY environment variable is required for YouTube search")
    end
  end

  defp check_api_key("facebook_ad_companies") do
    unless Mulberry.config(:scrapecreators_api_key) do
      Mix.raise(
        "SCRAPECREATORS_API_KEY environment variable is required for Facebook Ad Companies search"
      )
    end
  end

  defp check_api_key("google_ads") do
    unless Mulberry.config(:scrapecreators_api_key) do
      Mix.raise("SCRAPECREATORS_API_KEY environment variable is required for Google Ads search")
    end
  end

  defp validate_options(opts, type) do
    opts = validate_format(opts)
    opts = validate_limit(opts)
    opts = validate_reddit_options(opts, type)
    opts = validate_facebook_ads_options(opts, type)
    opts = validate_youtube_options(opts, type)
    opts
  end

  defp validate_format(opts) do
    case opts[:format] do
      nil ->
        Keyword.put(opts, :format, "text")

      format when format in ["text", "json", "markdown"] ->
        opts

      format ->
        Mix.raise("Invalid format: #{format}. Must be text, json, or markdown")
    end
  end

  defp validate_limit(opts) do
    case opts[:limit] do
      nil ->
        Keyword.put(opts, :limit, 10)

      limit when limit > 0 ->
        opts

      limit ->
        Mix.raise("Invalid limit: #{limit}. Must be greater than 0")
    end
  end

  defp validate_reddit_options(opts, "reddit") do
    opts =
      case opts[:sort] do
        nil ->
          opts

        sort when sort in ["relevance", "hot", "top", "new", "comments"] ->
          opts

        sort ->
          Mix.raise("Invalid sort: #{sort}. Must be relevance, hot, top, new, or comments")
      end

    case opts[:timeframe] do
      nil ->
        opts

      timeframe when timeframe in ["all", "year", "month", "week", "day", "hour"] ->
        opts

      timeframe ->
        Mix.raise("Invalid timeframe: #{timeframe}. Must be all, year, month, week, day, or hour")
    end
  end

  defp validate_reddit_options(opts, _), do: opts

  defp validate_facebook_ads_options(opts, "facebook_ads") do
    opts
    |> validate_search_by()
    |> validate_status()
    |> validate_media_type()
  end

  defp validate_facebook_ads_options(opts, _), do: opts

  defp validate_search_by(opts) do
    case opts[:search_by] do
      nil ->
        opts

      search_by when search_by in ["company_name", "page_id"] ->
        Keyword.put(opts, :search_by, String.to_atom(search_by))

      search_by ->
        Mix.raise("Invalid search_by: #{search_by}. Must be company_name or page_id")
    end
  end

  defp validate_status(opts) do
    case opts[:status] do
      nil ->
        opts

      status when status in ["ACTIVE", "INACTIVE", "ALL"] ->
        opts

      status ->
        Mix.raise("Invalid status: #{status}. Must be ACTIVE, INACTIVE, or ALL")
    end
  end

  defp validate_media_type(opts) do
    case opts[:media_type] do
      nil ->
        opts

      media_type when media_type in ["ALL", "image", "video", "meme"] ->
        opts

      media_type ->
        Mix.raise("Invalid media_type: #{media_type}. Must be ALL, image, video, or meme")
    end
  end

  defp validate_youtube_options(opts, "youtube") do
    opts
    |> validate_upload_date()
    |> validate_sort_by()
    |> validate_filter()
  end

  defp validate_youtube_options(opts, _), do: opts

  defp validate_upload_date(opts) do
    case opts[:upload_date] do
      nil ->
        opts

      date when date in ["lastHour", "today", "thisWeek", "thisMonth", "thisYear"] ->
        opts

      date ->
        Mix.raise(
          "Invalid upload_date: #{date}. Must be lastHour, today, thisWeek, thisMonth, or thisYear"
        )
    end
  end

  defp validate_sort_by(opts) do
    case opts[:sort_by] do
      nil ->
        opts

      sort when sort in ["relevance", "uploadDate", "viewCount", "rating"] ->
        opts

      sort ->
        Mix.raise("Invalid sort_by: #{sort}. Must be relevance, uploadDate, viewCount, or rating")
    end
  end

  defp validate_filter(opts) do
    case opts[:filter] do
      nil ->
        opts

      filter when filter in ["video", "channel", "playlist"] ->
        opts

      filter ->
        Mix.raise("Invalid filter: #{filter}. Must be video, channel, or playlist")
    end
  end

  defp perform_search(Mulberry.Search.Brave, query, opts) do
    # Build Brave-specific options
    brave_opts = []
    brave_opts = maybe_add_option(brave_opts, :result_filter, opts[:result_filter] || "query,web")

    case Mulberry.Search.Brave.search(query, opts[:limit], brave_opts) do
      {:ok, %Mulberry.Retriever.Response{content: content}} ->
        Mulberry.Search.Brave.to_documents(content)

      {:ok, response} ->
        Mulberry.Search.Brave.to_documents(response)

      error ->
        error
    end
  end

  defp perform_search(Mulberry.Search.Google, query, opts) do
    # Build Google-specific options
    google_opts = []
    google_opts = maybe_add_option(google_opts, :region, opts[:region])

    case Mulberry.Search.Google.search(query, opts[:limit], google_opts) do
      {:ok, %Mulberry.Retriever.Response{content: content}} ->
        Mulberry.Search.Google.to_documents(content)

      {:ok, response} ->
        Mulberry.Search.Google.to_documents(response)

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
    query =
      if subreddit = opts[:subreddit] do
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

  defp perform_search(Mulberry.Search.FacebookAds, query, opts) do
    # Build Facebook Ads-specific options
    fb_opts = []
    fb_opts = maybe_add_option(fb_opts, :search_by, opts[:search_by])
    fb_opts = maybe_add_option(fb_opts, :country, opts[:country])
    fb_opts = maybe_add_option(fb_opts, :status, opts[:status])
    fb_opts = maybe_add_option(fb_opts, :media_type, opts[:media_type])
    fb_opts = maybe_add_option(fb_opts, :cursor, opts[:cursor])
    fb_opts = maybe_add_option(fb_opts, :trim, opts[:trim])

    case Mulberry.Search.FacebookAds.search(query, opts[:limit], fb_opts) do
      {:ok, %Mulberry.Retriever.Response{content: content}} ->
        Mulberry.Search.FacebookAds.to_documents(content)

      {:ok, response} ->
        Mulberry.Search.FacebookAds.to_documents(response)

      error ->
        error
    end
  end

  defp perform_search(Mulberry.Search.YouTube, query, opts) do
    # Build YouTube-specific options
    youtube_opts = []
    youtube_opts = maybe_add_option(youtube_opts, :upload_date, opts[:upload_date])
    youtube_opts = maybe_add_option(youtube_opts, :sort_by, opts[:sort_by])
    youtube_opts = maybe_add_option(youtube_opts, :filter, opts[:filter])
    youtube_opts = maybe_add_option(youtube_opts, :continuation_token, opts[:continuation_token])

    case Mulberry.Search.YouTube.search(query, opts[:limit], youtube_opts) do
      {:ok, %Mulberry.Retriever.Response{content: content}} ->
        Mulberry.Search.YouTube.to_documents(content)

      {:ok, response} ->
        Mulberry.Search.YouTube.to_documents(response)

      error ->
        error
    end
  end

  defp perform_search(Mulberry.Search.FacebookAdCompanies, query, opts) do
    # Build Facebook Ad Companies-specific options
    fb_companies_opts = []
    fb_companies_opts = maybe_add_option(fb_companies_opts, :cursor, opts[:cursor])

    case Mulberry.Search.FacebookAdCompanies.search(query, opts[:limit], fb_companies_opts) do
      {:ok, %Mulberry.Retriever.Response{content: content}} ->
        Mulberry.Search.FacebookAdCompanies.to_documents(content)

      {:ok, response} ->
        Mulberry.Search.FacebookAdCompanies.to_documents(response)

      error ->
        error
    end
  end

  defp perform_search(Mulberry.Search.GoogleAds, query, opts) do
    # Build Google Ads-specific options
    google_ads_opts = []
    google_ads_opts = maybe_add_option(google_ads_opts, :advertiser_id, opts[:advertiser_id])
    google_ads_opts = maybe_add_option(google_ads_opts, :topic, opts[:topic])
    google_ads_opts = maybe_add_option(google_ads_opts, :region, opts[:region])
    google_ads_opts = maybe_add_option(google_ads_opts, :cursor, opts[:cursor])

    # If advertiser_id is provided, use nil for domain query
    query = if opts[:advertiser_id], do: nil, else: query

    case Mulberry.Search.GoogleAds.search(query, opts[:limit], google_ads_opts) do
      {:ok, %Mulberry.Retriever.Response{content: content}} ->
        Mulberry.Search.GoogleAds.to_documents(content)

      {:ok, response} ->
        Mulberry.Search.GoogleAds.to_documents(response)

      error ->
        error
    end
  end

  defp maybe_add_option(list, _key, nil), do: list
  defp maybe_add_option(list, key, value), do: Keyword.put(list, key, value)

  defp handle_success(documents, opts, type) do
    # Format the output
    output =
      case opts[:format] do
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

  defp format_text(documents, "youtube") do
    documents
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {doc, index} ->
      # Determine document type and format accordingly
      case doc.__struct__ do
        Mulberry.Document.YouTubeVideo ->
          format_youtube_video_text(doc, index)

        Mulberry.Document.YouTubeChannel ->
          format_youtube_channel_text(doc, index)

        Mulberry.Document.YouTubePlaylist ->
          format_youtube_playlist_text(doc, index)

        Mulberry.Document.YouTubeShort ->
          format_youtube_short_text(doc, index)
      end
    end)
  end

  defp format_text(documents, "reddit") do
    documents
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {doc, index} ->
      # Handle RedditPost documents with direct field access
      score = Map.get(doc, :score, 0)
      author = Map.get(doc, :author, "unknown")
      subreddit = Map.get(doc, :subreddit, "unknown")
      comments = Map.get(doc, :num_comments, 0)
      selftext = Map.get(doc, :selftext, "")

      """
      #{index}. #{doc.title}
      ───────────────────────────────────────────────────────────────────────────────
      📍 r/#{subreddit} | 👤 #{author} | ⬆️ #{score} | 💬 #{comments}
      #{format_description(selftext)}
      🔗 #{doc.url}
      """
    end)
  end

  defp format_text(documents, "facebook_ads") do
    documents
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {doc, index} ->
      # Handle FacebookAd documents with direct field access
      status = if doc.is_active, do: "Active", else: "Inactive"
      platforms = format_platforms(doc.publisher_platform)
      body = doc.body_text || "(No ad text)"

      """
      #{index}. #{doc.page_name}
      ───────────────────────────────────────────────────────────────────────────────
      📢 #{status} | 📱 #{platforms} | #{if doc.cta_text, do: "🔗 " <> doc.cta_text, else: ""}
      #{format_description(body)}
      #{if doc.link_url, do: "🔗 " <> doc.link_url, else: ""}
      """
    end)
  end

  defp format_text(documents, "facebook_ad_companies") do
    documents
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {doc, index} ->
      verification = if doc.verification, do: " ✓ #{doc.verification}", else: ""
      likes = if doc.likes, do: "👍 #{format_number(doc.likes)} likes", else: ""

      ig_info =
        if doc.ig_username,
          do: " | 📸 @#{doc.ig_username} (#{format_number(doc.ig_followers || 0)} followers)",
          else: ""

      """
      #{index}. #{doc.name}#{verification}
      ───────────────────────────────────────────────────────────────────────────────
      📂 #{doc.category || "N/A"} | #{likes}#{ig_info}
      📍 #{doc.country || "Unknown location"}
      Page ID: #{doc.page_id}
      """
    end)
  end

  defp format_text(documents, "google_ads") do
    documents
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {doc, index} ->
      date_range = format_date_range(doc.first_shown, doc.last_shown)

      """
      #{index}. #{doc.advertiser_name || "Unknown Advertiser"}
      ───────────────────────────────────────────────────────────────────────────────
      📱 Format: #{doc.format || "N/A"} | 🌐 Domain: #{doc.domain || "N/A"}
      📅 #{date_range}
      🔗 #{doc.ad_url || "No URL available"}
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

  defp format_markdown(documents, "youtube") do
    header = "# YouTube Search Results\n\n"

    results =
      documents
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {doc, index} ->
        case doc.__struct__ do
          Mulberry.Document.YouTubeVideo ->
            format_youtube_video_markdown(doc, index)

          Mulberry.Document.YouTubeChannel ->
            format_youtube_channel_markdown(doc, index)

          Mulberry.Document.YouTubePlaylist ->
            format_youtube_playlist_markdown(doc, index)

          Mulberry.Document.YouTubeShort ->
            format_youtube_short_markdown(doc, index)
        end
      end)

    header <> results
  end

  defp format_markdown(documents, "reddit") do
    header = "# Reddit Search Results\n\n"

    results =
      documents
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {doc, index} ->
        meta = format_reddit_metadata(doc)

        """
        ## #{index}. #{doc.title}

        #{meta}

        #{doc.selftext || "_No description_"}

        **[View on Reddit](#{doc.url})**
        """
      end)

    header <> results
  end

  defp format_markdown(documents, "facebook_ads") do
    header = "# Facebook Ads Search Results\n\n"

    results =
      documents
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {doc, index} ->
        status = if doc.is_active, do: "✅ Active", else: "❌ Inactive"

        """
        ## #{index}. #{doc.page_name}

        | Status | Platforms | CTA | Ad ID |
        |--------|-----------|-----|-------|
        | #{status} | #{format_platforms(doc.publisher_platform)} | #{doc.cta_text || "N/A"} | #{doc.ad_archive_id} |

        ### Ad Content

        #{doc.body_text || "_No ad text_"}

        #{if doc.link_url, do: "**[#{doc.cta_text || "View Link"}](#{doc.link_url})**", else: ""}
        """
      end)

    header <> results
  end

  defp format_markdown(documents, _type) do
    header = "# Search Results\n\n"

    results =
      documents
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {doc, index} ->
        """
        ## #{index}. [#{doc.title || "Untitled"}](#{doc.url})

        #{doc.description || "_No description_"}
        """
      end)

    header <> results
  end

  # Helper functions for YouTube formatting
  defp format_youtube_video_text(doc, index) do
    channel_name = if doc.channel, do: doc.channel.title, else: "Unknown"

    """
    #{index}. [VIDEO] #{doc.title}
    ───────────────────────────────────────────────────────────────────────────────
    📺 #{channel_name} | 👁️ #{doc.view_count_text || "N/A"} | ⏱️ #{doc.length_text || "N/A"}
    📅 #{doc.published_time_text || "N/A"}#{if doc.badges != [], do: " | 🏷️ #{Enum.join(doc.badges, ", ")}", else: ""}
    🔗 #{doc.url}
    """
  end

  defp format_youtube_channel_text(doc, index) do
    """
    #{index}. [CHANNEL] #{doc.title}
    ───────────────────────────────────────────────────────────────────────────────
    👥 #{doc.subscriber_count || "N/A"} subscribers | 📹 #{doc.video_count || "N/A"} videos
    #{if doc.handle, do: "🔖 #{doc.handle}", else: ""}
    #{if doc.description, do: format_description(doc.description), else: ""}
    #{if doc.url, do: "🔗 #{doc.url}", else: ""}
    """
  end

  defp format_youtube_playlist_text(doc, index) do
    channel_name = if doc.channel, do: doc.channel.title, else: "Unknown"

    """
    #{index}. [PLAYLIST] #{doc.title}
    ───────────────────────────────────────────────────────────────────────────────
    📺 #{channel_name} | 📹 #{doc.video_count_text || "N/A"}
    #{if doc.first_video, do: "▶️ First: #{doc.first_video.title}", else: ""}
    🔗 #{doc.url}
    """
  end

  defp format_youtube_short_text(doc, index) do
    channel_name = if doc.channel, do: doc.channel.title, else: "Unknown"

    """
    #{index}. [SHORT] #{doc.title}
    ───────────────────────────────────────────────────────────────────────────────
    📱 #{channel_name} | 👁️ #{doc.view_count_text || "N/A"} | ⏱️ #{doc.length_text || "N/A"}
    📅 #{doc.published_time_text || "N/A"}
    🔗 #{doc.url}
    """
  end

  defp format_youtube_video_markdown(doc, index) do
    channel_name = if doc.channel, do: doc.channel.title, else: "Unknown"

    """
    ## #{index}. 🎬 [#{doc.title}](#{doc.url})

    **Channel:** #{channel_name}  
    **Views:** #{doc.view_count_text || "N/A"} | **Duration:** #{doc.length_text || "N/A"} | **Published:** #{doc.published_time_text || "N/A"}
    #{if doc.badges != [], do: "\n**Badges:** #{Enum.join(doc.badges, ", ")}", else: ""}
    """
  end

  defp format_youtube_channel_markdown(doc, index) do
    """
    ## #{index}. 📺 [#{doc.title}](#{doc.url || "#"})

    **Type:** Channel  
    **Subscribers:** #{doc.subscriber_count || "N/A"} | **Videos:** #{doc.video_count || "N/A"}
    #{if doc.handle, do: "\n**Handle:** #{doc.handle}", else: ""}
    #{if doc.description, do: "\n#{doc.description}", else: ""}
    """
  end

  defp format_youtube_playlist_markdown(doc, index) do
    channel_name = if doc.channel, do: doc.channel.title, else: "Unknown"

    """
    ## #{index}. 📋 [#{doc.title}](#{doc.url})

    **Type:** Playlist  
    **Channel:** #{channel_name} | **Videos:** #{doc.video_count_text || "N/A"}
    #{if doc.first_video, do: "\n**First Video:** #{doc.first_video.title}", else: ""}
    """
  end

  defp format_youtube_short_markdown(doc, index) do
    channel_name = if doc.channel, do: doc.channel.title, else: "Unknown"

    """
    ## #{index}. 📱 [#{doc.title}](#{doc.url})

    **Type:** Short  
    **Channel:** #{channel_name}  
    **Views:** #{doc.view_count_text || "N/A"} | **Duration:** #{doc.length_text || "N/A"} | **Published:** #{doc.published_time_text || "N/A"}
    """
  end

  defp format_reddit_metadata(doc) do
    """
    | Subreddit | Author | Score | Comments | Created |
    |-----------|--------|-------|----------|---------|
    | r/#{doc.subreddit} | u/#{doc.author} | #{doc.score} | #{doc.num_comments} | #{format_timestamp(doc.created_at_iso)} |
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

  defp format_platforms(nil), do: "Unknown"
  defp format_platforms([]), do: "Unknown"
  defp format_platforms(platforms), do: Enum.join(platforms, ", ")

  defp format_number(nil), do: "0"

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_number(num), do: to_string(num)

  defp format_date_range(nil, nil), do: "Date range unknown"
  defp format_date_range(first, nil), do: "First shown: #{first}"
  defp format_date_range(nil, last), do: "Last shown: #{last}"
  defp format_date_range(first, last), do: "#{first} → #{last}"

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
