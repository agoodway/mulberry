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

In your `runtime.exs`:

```elixir
config :langchain, openai_key: System.get_env("OPENAI_API_KEY")
config :mulberry, brave_api_key: System.get_env("BRAVE_API_KEY")
```

## Examples

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
- [ ] Typesense Search Adapter
- [ ] Streaming audio and video support
- [ ] Agents
- [ ] Implement other file types
- [ ] Backfill tests
- [ ] and much much more...


Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/mulberry>.
