# Mulberry (Very Alpha)

An AI package for Elixir that focuses on higher level application concerns. It will include an AI UI component library for [Phoenix](https://github.com/phoenixframework/phoenix).

## Installation

In your `mix.exs`:

**While in active Alpha development it is probably best to pull it from Github**

```elixir
def deps do
  [
    {:mulberry, github: "agoodway/mulberry", branch: "main"}
  ]
end
```

```elixir
def deps do
  [
    {:mulberry, "~> 0.1.0"}
  ]
end
```

## Configuration

### Basic Configuration

Mulberry now includes a flexible LangChain configuration system that supports multiple LLM providers with sensible defaults. The simplest configuration uses environment variables:

```bash
# Choose your provider (defaults to :openai)
export MULBERRY_LLM_PROVIDER=openai

# Set API keys for the providers you want to use
export OPENAI_API_KEY=your-openai-key
export ANTHROPIC_API_KEY=your-anthropic-key

# For Brave search functionality
export BRAVE_API_KEY=your-brave-key
```

### Advanced Configuration

You can configure LangChain providers programmatically in your `runtime.exs`:

```elixir
# Legacy configuration (still supported)
config :langchain, openai_key: System.get_env("OPENAI_API_KEY")
config :mulberry, brave_api_key: System.get_env("BRAVE_API_KEY")

# New configuration system (optional - defaults are provided)
config :mulberry, :langchain,
  default_provider: :openai,
  providers: [
    openai: [
      model: "gpt-4",
      temperature: 0.7
    ],
    anthropic: [
      model: "claude-3-opus-20240229",
      temperature: 0.5
    ]
  ]

# Enable verbose logging for debugging
config :mulberry, :verbose_logging, true
```

### Supported LLM Providers

- `:openai` - OpenAI's GPT models (default)
- `:anthropic` - Anthropic's Claude models
- `:google` - Google's Gemini models
- `:mistral` - Mistral AI models
- `:ollama` - Local Ollama models
- `:vertex_ai` - Google Vertex AI
- `:bumblebee` - Local Bumblebee models

### Environment Variables

Each provider supports configuration through environment variables:

- `MULBERRY_LLM_PROVIDER` - Default provider to use
- `MULBERRY_[PROVIDER]_API_KEY` - API key for specific provider
- `MULBERRY_[PROVIDER]_MODEL` - Default model for provider
- `MULBERRY_[PROVIDER]_TEMPERATURE` - Temperature setting
- `MULBERRY_[PROVIDER]_MAX_TOKENS` - Max tokens setting
- `MULBERRY_[PROVIDER]_ENDPOINT` - Custom endpoint URL

Examples:
```bash
export MULBERRY_OPENAI_MODEL=gpt-4
export MULBERRY_ANTHROPIC_MODEL=claude-3-opus-20240229
export MULBERRY_OLLAMA_ENDPOINT=http://localhost:11434/api/chat
```

## Examples

### Using Different LLM Providers

```elixir
# Use default provider (OpenAI by default)
{:ok, summary} = Mulberry.Text.summarize("Long text to summarize...")

# Use Anthropic's Claude
{:ok, summary} = Mulberry.Text.summarize("Long text...", provider: :anthropic)

# Use Google's Gemini with custom temperature
{:ok, summary} = Mulberry.Text.summarize("Long text...", 
  provider: :google, 
  temperature: 0.2
)

# Generate title with Mistral AI
{:ok, title} = Mulberry.Text.title("Article content...", 
  provider: :mistral,
  model: "mistral-large"
)

# Use local Ollama installation
{:ok, summary} = Mulberry.Text.summarize("Long text...", 
  provider: :ollama,
  model: "llama2",
  endpoint: "http://localhost:11434/api/chat"
)
```

### Extract text from a PDF or image file in a Phoenix upload:

```elixir
import Flamel.Wrap, only: [ok: 1]
alias Mulberry.Document
alias Flamel.Result

defp handle_upload(socket, entry) do
  {:ok, text} =
    consume_uploaded_entry(socket, entry, fn %{path: path} ->
      %{path: path, mime: entry.client_type}
      |> Document.File.new()
      |> Document.load()
      |> Result.map(fn file -> file.contents end)
      |> ok()
    end)

  socket
  |> assign(:file, AsyncResult.loading())
  |> start_async(:file, fn -> Files.parse_text(text) end)
end
```

The above example uses [Flamel](https://github.com/themusicman/flamel) to handle :ok and :error tuples. See [`Result.map/2`](https://hexdocs.pm/flamel/1.10.0/Flamel.Result.html#map/2) and [`ok/1`](https://hexdocs.pm/flamel/1.10.0/Flamel.Wrap.html#ok/1)


### Generate a summary of a web pages from a [Brave Search API](https://brave.com/search/api/) query:

```elixir
alias Mulberry.Search.Brave
alias Mulberry.Document

# this chain can be applied to any Mulberry.Document whether it is a web page or an image file
def load_and_generate_summary(chain) do
  chain
  |> Chain.apply(&Document.load/1)
  |> Chain.apply(&Document.generate_summary/1)
  |> Chain.to_tuple()
end

Mulberry.search(Brave, "what is the best cake recipe?")
# apply this sequence of operations to each document returned from the search query
|> Enum.map(Chain.curry(&load_and_generate_summary/1))
# remove any results that resulted in an error
|> Enum.filter(&Result.ok?/1)
```

The above example uses [Flamel](https://github.com/themusicman/flamel) chain a couple operations on the document and filter non-ok results. See [`Flamel.Chain`](https://hexdocs.pm/flamel/1.10.0/Flamel.Chain.html) and [`Result.ok?/1`](https://hexdocs.pm/flamel/1.10.0/Flamel.Result.html#ok?/1)

### Web Scraping with Different Retrievers

Mulberry supports multiple retriever strategies for fetching web content:

```elixir
# Use default retriever (Req)
{:ok, webpage} = Mulberry.Document.WebPage.new("https://example.com")
                 |> Mulberry.Document.load()

# Use Playwright for JavaScript-heavy sites
{:ok, webpage} = Mulberry.Document.WebPage.new("https://spa-app.com")
                 |> Mulberry.Document.load(retriever: Mulberry.Retriever.Playwright)

# Use ScrapingBee with API key
{:ok, webpage} = Mulberry.Document.WebPage.new("https://protected-site.com")
                 |> Mulberry.Document.load(
                   retriever: Mulberry.Retriever.ScrapingBee,
                   api_key: "your-scrapingbee-key"
                 )

# Try multiple retrievers in sequence
retrievers = [Mulberry.Retriever.Req, Mulberry.Retriever.Playwright]
{:ok, webpage} = Mulberry.Document.WebPage.new("https://example.com")
                 |> Mulberry.Document.load(retriever: retrievers)
```

### Converting Web Pages to Different Formats

```elixir
# Load a webpage and convert to Markdown
{:ok, webpage} = Mulberry.Document.WebPage.new("https://blog.example.com/article")
                 |> Mulberry.Document.load()

{:ok, markdown} = Mulberry.Document.to_text(webpage)

# Convert HTML to Markdown directly
html = "<h1>Title</h1><p>Some <strong>bold</strong> text</p>"
{:ok, markdown} = Mulberry.HTML.to_markdown(html)
# => "# Title\n\nSome **bold** text"

# Extract clean text from HTML
html_tree = Floki.parse_document!(html)
text = Mulberry.HTML.to_readable_text(html_tree)
```

### Advanced Text Processing

```elixir
# Summarize with custom options
article = "Long article text..."
{:ok, summary} = Mulberry.Text.summarize(article,
  provider: :anthropic,
  model: "claude-3-haiku-20240307",
  max_tokens: 150,
  system_message: "Summarize in bullet points"
)

# Generate keywords
{:ok, keywords} = Mulberry.Text.keywords(article, 
  count: 10,
  provider: :openai
)

# Create a title with specific style
{:ok, title} = Mulberry.Text.title(article,
  system_message: "Create a catchy, SEO-friendly title under 60 characters"
)

# Generate title with examples to guide style
{:ok, title} = Mulberry.Text.title(article,
  examples: ["10 Ways to Boost Productivity", "The Ultimate Guide to Elixir"],
  max_words: 10
)

# Title generation with fallback
{:ok, title} = Mulberry.Text.title(article,
  fallback_title: "Technology Article",
  verbose: true
)

# Classify content
{:ok, category} = Mulberry.Text.classify(article,
  categories: ["Technology", "Business", "Health", "Sports"],
  provider: :google
)

# Enable verbose logging for debugging
{:ok, summary} = Mulberry.Text.summarize(article, verbose: true)
```

### Working with the Mix Task

```elixir
# Fetch and display a webpage
mix fetch_url https://example.com

# Save webpage as HTML
mix fetch_url https://example.com --save page.html

# Convert to Markdown and save
mix fetch_url https://example.com --markdown --save article.md

# Extract text content only
mix fetch_url https://example.com --show-text

# Use specific browser and wait for content
mix fetch_url https://spa-app.com --browser firefox --wait-for "#content"

# Non-headless mode for debugging
mix fetch_url https://example.com --no-headless

# Disable stealth mode for faster scraping
mix fetch_url https://example.com --no-stealth
```

### Processing Multiple Documents

```elixir
# Process search results in parallel
alias Mulberry.{Search, Document, Text}

urls = [
  "https://example1.com",
  "https://example2.com", 
  "https://example3.com"
]

# Load all pages concurrently
tasks = Enum.map(urls, fn url ->
  Task.async(fn ->
    Document.WebPage.new(url)
    |> Document.load()
  end)
end)

webpages = Task.await_many(tasks, 30_000)
           |> Enum.filter(&match?({:ok, _}, &1))
           |> Enum.map(fn {:ok, page} -> page end)

# Generate summaries for all pages
summaries = webpages
            |> Enum.map(&Document.to_text/1)
            |> Enum.map(fn {:ok, text} -> 
              Task.async(fn -> Text.summarize(text) end)
            end)
            |> Task.await_many(30_000)
```

### Custom LLM Integration

```elixir
# Create a custom LLM function
custom_llm = fn messages, _config ->
  # Your custom LLM implementation
  response = MyLLMService.chat(messages)
  {:ok, response}
end

# Use with Mulberry functions
{:ok, summary} = Mulberry.Text.summarize("Text to summarize",
  llm: custom_llm,
  system_message: "Custom instructions"
)

# Chain operations with custom LLM
import Flamel.Chain

webpage
|> Chain.apply(&Document.load/1)
|> Chain.apply(&Document.to_text/1)
|> Chain.apply(&Text.summarize(&1, llm: custom_llm))
|> Chain.to_tuple()
```

### Working with Local Files

```elixir
# Extract text from various file types
alias Mulberry.Document

# PDF file
{:ok, pdf} = Document.File.new(%{path: "/path/to/document.pdf", mime: "application/pdf"})
             |> Document.load()
{:ok, text} = Document.to_text(pdf)

# Image with OCR
{:ok, image} = Document.File.new(%{path: "/path/to/scan.png", mime: "image/png"})
               |> Document.load()
{:ok, text} = Document.to_text(image)

# Process uploaded files in Phoenix
def handle_event("upload", _params, socket) do
  consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
    file = Document.File.new(%{path: path, mime: entry.client_type})
    
    with {:ok, doc} <- Document.load(file),
         {:ok, text} <- Document.to_text(doc),
         {:ok, summary} <- Text.summarize(text) do
      {:ok, %{filename: entry.client_name, summary: summary}}
    end
  end)
  |> case do
    [{:ok, result}] -> 
      {:noreply, assign(socket, :result, result)}
    _ -> 
      {:noreply, put_flash(socket, :error, "Failed to process file")}
  end
end
```

## TODO

- [ ] Text to audio
- [ ] Audio to text
- [ ] Video to text
- [ ] Add embeddings to Text module
- [ ] Typesense Search Adapter
- [ ] Streaming audio and video support
- [ ] Agents
- [ ] Implement other file types
- [ ] Backfill tests
- [ ] and much much more...


Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/mulberry>.
