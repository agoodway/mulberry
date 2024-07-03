defmodule Mulberry.Document.WebPage do
  @moduledoc false
  alias __MODULE__

  @type t :: %__MODULE__{
          url: String.t(),
          title: String.t(),
          description: String.t(),
          content: String.t(),
          markdown: String.t(),
          summary: String.t(),
          keywords: list(),
          meta: list()
        }

  defstruct url: nil,
            title: nil,
            description: nil,
            content: nil,
            markdown: nil,
            summary: nil,
            keywords: [],
            meta: []

  def new(attrs) do
    struct!(WebPage, attrs)
  end

  defimpl Mulberry.Document do
    require Logger
    alias Mulberry.Document
    alias Mulberry.Retriever
    alias Mulberry.Retriever.Response
    alias Mulberry.Text

    def load(%WebPage{} = web_page, opts \\ []) do
      retriever = Keyword.get(opts, :retriever, Retriever.Req)

      case Retriever.get(retriever, web_page.url) do
        {:ok, %Response{status: :ok, content: content}} ->
          Logger.debug("#{__MODULE__}.load/2 content=#{inspect(content)}")
          web_page = Map.replace(web_page, :content, content)

          web_page =
            case Html2Markdown.convert(content) do
              {:error, _error} ->
                web_page

              markdown ->
                Map.replace(web_page, :markdown, markdown)
            end

          {:ok, web_page}

        {:ok, _request} ->
          {:error, :load_failed, web_page}

        {:error, error} ->
          {:error, error, web_page}
      end
    end

    def generate_summary(web_page, _opts)

    def generate_summary(%WebPage{markdown: markdown} = web_page, _opts)
        when is_binary(markdown) do
      case Text.summarize(markdown) do
        {:ok, summary} ->
          {:ok, Map.replace(web_page, :summary, summary)}

        {:error, error} ->
          {:error, error, web_page}
      end
    end

    def generate_summary(%WebPage{} = web_page, _opts) do
      {:error, :not_loaded, web_page}
    end

    def generate_keywords(web_page, opts \\ [])

    def generate_keywords(%WebPage{markdown: markdown} = web_page, _opts)
        when is_binary(markdown) do
      {:ok, Map.replace(web_page, :keywords, [])}
    end

    def generate_keywords(%WebPage{} = web_page, _opts) do
      {:error, :not_loaded, web_page}
    end

    def generate_title(web_page, opts \\ [])

    def generate_title(%WebPage{markdown: markdown} = web_page, _opts)
        when is_binary(markdown) do
      if web_page.title do
        {:ok, web_page}
      else
        case Text.title(markdown) do
          {:ok, title} ->
            {:ok, Map.replace(web_page, :title, title)}

          {:error, error} ->
            {:error, error, web_page}
        end
      end
    end

    def generate_title(%WebPage{} = web_page, _opts) do
      {:error, :not_loaded, web_page}
    end

    def to_text(web_page, opts \\ [])

    def to_text(%WebPage{markdown: markdown} = web_page, _opts) when is_binary(markdown) do
      {:ok, web_page.markdown}
    end

    def to_text(%WebPage{} = _web_page, _opts) do
      {:error, :not_loaded}
    end

    def to_tokens(web_page, opts \\ [])

    def to_tokens(%WebPage{markdown: markdown} = web_page, opts)
        when is_binary(markdown) do
      with {:ok, text} <- Document.to_text(web_page, opts),
           {:ok, tokens} <- Text.tokens(text) do
        {:ok, tokens}
      else
        _ ->
          {:error, :tokenization_failed}
      end
    end

    def to_tokens(%WebPage{} = _web_page, _opts) do
      {:error, :not_loaded}
    end

    def to_chunks(web_page, opts \\ [])

    def to_chunks(%WebPage{markdown: markdown} = web_page, _opts)
        when is_binary(markdown) do
      case Text.split(web_page.markdown) do
        {:ok, chunks} ->
          {:ok, chunks}

        {:error, error} ->
          {:error, error}
      end
    end

    def to_chunks(%WebPage{} = _web_page, _opts) do
      {:error, :not_loaded}
    end
  end
end
