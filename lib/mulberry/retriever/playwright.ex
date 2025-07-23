defmodule Mulberry.Retriever.Playwright do
  @moduledoc """
  Retriever implementation using Playwright for browser-based content fetching.
  Useful for pages that require JavaScript execution or dynamic content loading.
  
  Includes bot detection evasion features such as:
  - Realistic user agents
  - Common viewport sizes
  - Random delays between actions
  - Non-headless mode option
  - Human-like scrolling behavior
  
  ## Options
  
  * `:browser` - Browser type to use (:chromium, :firefox, :webkit). Default: :chromium
  * `:headless` - Whether to run browser in headless mode. Default: true
  * `:user_agent` - Custom user agent string. Default: randomly selected from common agents
  * `:viewport` - Map with :width and :height keys. Default: randomly selected common size
  * `:stealth_mode` - Enable/disable stealth features. Default: true
  * `:delay_range` - Tuple {min, max} for random delays in ms. Default: {100, 500}
  * `:proxy` - Proxy configuration map
  * `:locale` - Browser locale. Default: "en-US"
  * `:timezone` - Timezone ID. Default: "America/New_York"
  * `:wait_for_selector` - CSS selector to wait for. Default: "body"
  * `:browser_args` - Additional browser launch arguments
  
  ## Examples
  
      # Basic usage with default stealth settings
      Mulberry.Retriever.Playwright.get("https://example.com")
      
      # Custom configuration with visible browser
      Mulberry.Retriever.Playwright.get("https://example.com",
        user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64)...",
        viewport: %{width: 1920, height: 1080},
        headless: false,
        delay_range: {200, 800}
      )
      
      # With proxy
      Mulberry.Retriever.Playwright.get("https://example.com",
        proxy: %{
          server: "http://proxy.example.com:8080",
          username: "user",
          password: "pass"
        }
      )
      
      # Disable stealth mode for faster scraping
      Mulberry.Retriever.Playwright.get("https://example.com",
        stealth_mode: false,
        headless: true
      )
  """
  
  @behaviour Mulberry.Retriever
  require Logger

  # Common user agents for rotation
  @user_agents [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Safari/605.1.15"
  ]

  # Common viewport sizes
  @viewports [
    %{width: 1920, height: 1080},
    %{width: 1366, height: 768},
    %{width: 1536, height: 864},
    %{width: 1440, height: 900},
    %{width: 1280, height: 720}
  ]

  @impl true
  def get(url, opts \\ []) do
    responder = Keyword.get(opts, :responder, &Mulberry.Retriever.Response.default_responder/1)
    
    with {:ok, browser} <- launch_browser(opts),
         {:ok, page} <- setup_page(browser, opts),
         {:ok, html} <- fetch_content(page, url, opts) do
      
      Playwright.Page.close(page)
      Playwright.Browser.close(browser)
      
      responder.(%Mulberry.Retriever.Response{status: :ok, content: html})
    else
      {:error, reason} ->
        Logger.error("Playwright retriever error: #{inspect(reason)}")
        responder.(%Mulberry.Retriever.Response{status: :failed, content: nil})
    end
  end

  @spec launch_browser(Keyword.t()) :: {:ok, Playwright.Browser.t()} | {:error, any()}
  defp launch_browser(opts) do
    browser_type = Keyword.get(opts, :browser, :chromium)
    headless = Keyword.get(opts, :headless, true)
    
    launch_options = %{
      headless: headless,
      args: browser_args(opts)
    }

    # Add proxy if configured
    launch_options = 
      case Keyword.get(opts, :proxy) do
        nil -> launch_options
        proxy_config -> Map.put(launch_options, :proxy, proxy_config)
      end

    case Playwright.launch(browser_type, launch_options) do
      {:ok, browser} -> {:ok, browser}
      error -> {:error, {:browser_launch_failed, error}}
    end
  end

  @spec browser_args(Keyword.t()) :: [String.t()]
  defp browser_args(opts) do
    base_args = [
      "--disable-blink-features=AutomationControlled",
      "--disable-dev-shm-usage",
      "--no-sandbox",
      "--disable-setuid-sandbox",
      "--disable-web-security",
      "--disable-features=IsolateOrigins,site-per-process"
    ]

    # Add custom args if provided
    custom_args = Keyword.get(opts, :browser_args, [])
    base_args ++ custom_args
  end

  @spec setup_page(Playwright.Browser.t(), Keyword.t()) :: {:ok, Playwright.Page.t()} | {:error, any()}
  defp setup_page(browser, opts) do
    user_agent = get_user_agent(opts)
    viewport = get_viewport(opts)

    context_options = %{
      user_agent: user_agent,
      viewport: viewport,
      locale: Keyword.get(opts, :locale, "en-US"),
      timezone_id: Keyword.get(opts, :timezone, "America/New_York")
    }

    # Create context with options
    context = Playwright.Browser.new_context(browser, context_options)
    
    # Create page from context
    case Playwright.BrowserContext.new_page(context) do
      page when is_struct(page) -> 
        # Set additional page configurations
        configure_page(page, opts)
        {:ok, page}
      error -> 
        {:error, {:page_creation_failed, error}}
    end
  end

  @spec configure_page(Playwright.Page.t(), Keyword.t()) :: :ok
  defp configure_page(page, opts) do
    # Override navigator.webdriver property
    Playwright.Page.add_init_script(page, """
      Object.defineProperty(navigator, 'webdriver', {
        get: () => undefined
      });
    """)

    # Add random mouse movements if stealth mode is enabled
    if Keyword.get(opts, :stealth_mode, true) do
      Playwright.Page.add_init_script(page, """
        // Random mouse movement simulation
        let mouseX = Math.random() * window.innerWidth;
        let mouseY = Math.random() * window.innerHeight;
        
        document.addEventListener('DOMContentLoaded', () => {
          const event = new MouseEvent('mousemove', {
            clientX: mouseX,
            clientY: mouseY,
            bubbles: true
          });
          document.dispatchEvent(event);
        });
      """)
    end

    :ok
  end

  @spec get_user_agent(Keyword.t()) :: String.t()
  defp get_user_agent(opts) do
    case Keyword.get(opts, :user_agent) do
      nil -> Enum.random(@user_agents)
      ua -> ua
    end
  end

  @spec get_viewport(Keyword.t()) :: map()
  defp get_viewport(opts) do
    case Keyword.get(opts, :viewport) do
      nil -> Enum.random(@viewports)
      vp -> vp
    end
  end

  @spec fetch_content(Playwright.Page.t(), String.t(), Keyword.t()) :: {:ok, String.t()} | {:error, any()}
  defp fetch_content(page, url, opts) do
    stealth_mode = Keyword.get(opts, :stealth_mode, true)
    {min_delay, max_delay} = Keyword.get(opts, :delay_range, {100, 500})

    # Random delay before navigation
    if stealth_mode, do: random_delay(min_delay, max_delay)

    # Navigate to URL
    case Playwright.Page.goto(page, url, %{wait_until: "networkidle"}) do
      {:ok, _} -> :ok
      error -> {:error, {:navigation_failed, error}}
    end

    # Random delay after navigation
    if stealth_mode, do: random_delay(min_delay, max_delay)

    # Perform human-like actions
    if stealth_mode do
      perform_human_actions(page, min_delay, max_delay)
    end

    # Wait for content to load
    wait_for = Keyword.get(opts, :wait_for_selector, "body")
    Playwright.Page.wait_for_selector(page, wait_for, %{timeout: 30_000})

    # Final delay before extracting content
    if stealth_mode, do: random_delay(min_delay, max_delay)

    # Extract HTML content
    html = 
      page
      |> Playwright.Page.locator("html")
      |> Playwright.Locator.inner_html()

    {:ok, html}
  rescue
    e ->
      {:error, {:content_fetch_failed, e}}
  end

  @spec perform_human_actions(Playwright.Page.t(), integer(), integer()) :: :ok
  defp perform_human_actions(page, min_delay, max_delay) do
    # Random scrolling
    scroll_count = :rand.uniform(3) + 1
    
    Enum.each(1..scroll_count, fn _ ->
      scroll_amount = :rand.uniform(300) + 100
      
      Playwright.Page.evaluate(page, """
        window.scrollBy({
          top: #{scroll_amount},
          behavior: 'smooth'
        });
      """)
      
      random_delay(min_delay, max_delay)
    end)

    # Scroll back to top sometimes
    if :rand.uniform(2) == 1 do
      Playwright.Page.evaluate(page, """
        window.scrollTo({
          top: 0,
          behavior: 'smooth'
        });
      """)
      random_delay(min_delay, max_delay)
    end

    :ok
  end

  @spec random_delay(integer(), integer()) :: :ok
  defp random_delay(min, max) do
    delay = min + :rand.uniform(max - min)
    :timer.sleep(delay)
  end
end
