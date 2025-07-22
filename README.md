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

The chain above could be applied to ei

The above example uses [Flamel](https://github.com/themusicman/flamel) chain a couple operations on the document and filter non-ok results. See [`Flamel.Chain`](https://hexdocs.pm/flamel/1.10.0/Flamel.Chain.html) and [`Result.ok?/1`](https://hexdocs.pm/flamel/1.10.0/Flamel.Result.html#ok?/1)


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
