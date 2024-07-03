defmodule Mulberry.Document.File do
  @moduledoc false

  @type t :: %__MODULE__{
          path: String.t() | Path.t(),
          contents: any(),
          summary: String.t(),
          keywords: list(),
          title: String.t(),
          mime: String.t(),
          meta: list()
        }

  defstruct path: nil, contents: nil, summary: nil, keywords: [], title: nil, mime: nil, meta: []

  def new(attrs) do
    attrs = Map.put_new(attrs, :mime, MIME.from_path(attrs.path))
    struct!(Mulberry.Document.File, attrs)
  end

  defimpl Mulberry.Document do
    alias Mulberry.Document
    alias Mulberry.Text

    def load(file, opts \\ [])

    def load(%Mulberry.Document.File{path: path} = file, _opts) when is_binary(path) do
      case file.mime do
        "application/pdf" ->
          ocr_pdf(file)

        "image/png" ->
          ocr_image(file)

        "image/jpeg" ->
          ocr_image(file)

        "image/gif" ->
          ocr_image(file)

        "image/webp" ->
          ocr_image(file)

        "image/tiff" ->
          ocr_image(file)

        "text/plain" ->
          contents = File.read!(file.path)
          %{file | contents: contents}

        _ ->
          {:error, :unsupported_mime, file}
      end
    end

    def load(%Mulberry.Document.File{} = file, _opts) do
      {:error, :path_not_provided, file}
    end

    def generate_summary(file, opts \\ [])

    def generate_summary(%Mulberry.Document.File{contents: contents} = file, _opts)
        when is_binary(contents) do
      case Text.summarize(contents) do
        {:ok, summary} ->
          {:ok, %{file | summary: summary}}

        {:error, error} ->
          {:error, error, file}
      end
    end

    def generate_summary(%Mulberry.Document.File{} = file, _opts) do
      {:error, :not_loaded, file}
    end

    def generate_keywords(file, opts \\ [])

    def generate_keywords(%Mulberry.Document.File{contents: contents} = file, _opts)
        when is_binary(contents) do
      {:ok, file}
    end

    def generate_keywords(%Mulberry.Document.File{} = file, _opts) do
      {:error, :not_loaded, file}
    end

    def generate_title(file, opts \\ [])

    def generate_title(%Mulberry.Document.File{contents: contents} = file, _opts)
        when is_binary(contents) do
      case Text.title(contents) do
        {:ok, title} ->
          {:ok, %{file | title: title}}

        {:error, error} ->
          {:error, error, file}
      end
    end

    def generate_title(%Mulberry.Document.File{} = file, _opts) do
      {:error, :not_loaded, file}
    end

    def to_text(file, opts \\ [])

    def to_text(%Mulberry.Document.File{contents: contents} = file, _opts)
        when is_binary(contents) do
      {:ok, file.contents}
    end

    def to_text(%Mulberry.Document.File{} = file, _opts) do
      {:error, :not_loaded, file}
    end

    def to_tokens(file, opts \\ [])

    def to_tokens(%Mulberry.Document.File{contents: contents} = file, opts)
        when is_binary(contents) do
      with {:ok, text} <- Document.to_text(contents, opts),
           {:ok, tokens} <- Text.tokens(text) do
        {:ok, tokens}
      else
        _ ->
          {:error, :tokenization_failed, file}
      end
    end

    def to_tokens(%Mulberry.Document.File{} = file, _opts) do
      {:error, :not_loaded, file}
    end

    def to_chunks(file, opts \\ [])

    def to_chunks(%Mulberry.Document.File{contents: contents} = file, _opts)
        when is_binary(contents) do
      case Text.split(file.contents) do
        {:ok, chunks} ->
          {:ok, chunks}

        {:error, error} ->
          {:error, error, file}
      end
    end

    def to_chunks(%Mulberry.Document.File{} = file, _opts) do
      {:error, :not_loaded, file}
    end

    defp ocr_image(file) do
      text = TesseractOcr.read(file.path)
      file = Map.replace(file, :contents, text)
      {:ok, file}
    end

    defp ocr_pdf(file) do
      # case Rambo.run("pdftotext", ["-layout", file.path, "-"]) do
      #   {:ok, %Rambo{status: 0, out: contents}} ->
      #     file = Map.replace(file, :contents, contents)
      #     {:ok, file}
      #
      #   _ ->
      #     {:error, :parse_failed, file}
      # end
      case System.cmd("pdftotext", ["-layout", file.path, "-"]) do
        {contents, 0} ->
          file = Map.replace(file, :contents, contents)
          {:ok, file}

        _ ->
          {:error, :parse_failed, file}
      end
    end
  end
end
