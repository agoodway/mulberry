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
          meta: list(),
          type: String.t() | nil,
          network: String.t() | nil
        }

  defstruct url: nil,
            title: nil,
            description: nil,
            content: nil,
            markdown: nil,
            summary: nil,
            keywords: [],
            meta: [],
            type: nil,
            network: nil

  @doc """
  Creates a new WebPage document struct with the given attributes.
  """
  @spec new(map()) :: t()
  def new(attrs) do
    struct!(WebPage, attrs)
  end

  defimpl Mulberry.Document do
    require Logger
    alias Mulberry.Document
    alias Mulberry.DocumentTransformer
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
            case Mulberry.HTML.to_markdown(content) do
              {:error, _error} ->
                web_page

              {:ok, markdown} ->
                Map.replace(web_page, :markdown, markdown)
            end

          {:ok, web_page}

        {:ok, _request} ->
          {:error, :load_failed, web_page}

        {:error, error} ->
          {:error, error, web_page}
      end
    end

    # Transform function - new unified interface
    def transform(web_page, transformation, opts \\ [])

    def transform(%WebPage{} = web_page, transformation, opts) do
      transformer = Keyword.get(opts, :transformer, DocumentTransformer.Default)
      transformer.transform(web_page, transformation, opts)
    end

    # Backward compatibility functions
    def generate_summary(web_page, opts \\ []) do
      transform(web_page, :summary, opts)
    end

    def generate_keywords(web_page, opts \\ []) do
      transform(web_page, :keywords, opts)
    end

    def generate_title(web_page, opts \\ []) do
      transform(web_page, :title, opts)
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
      chunks = Text.split(web_page.markdown)
      {:ok, chunks}
    end

    def to_chunks(%WebPage{} = _web_page, _opts) do
      {:error, :not_loaded}
    end
  end
end
