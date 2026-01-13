defmodule Mulberry.Document.File do
  @moduledoc false

  require Logger

  @type t :: %__MODULE__{
          path: String.t() | Path.t(),
          contents: any(),
          summary: String.t(),
          keywords: list(),
          title: String.t(),
          extracted_data: list(map()) | nil,
          mime: String.t(),
          meta: list()
        }

  defstruct path: nil,
            contents: nil,
            summary: nil,
            keywords: [],
            title: nil,
            extracted_data: nil,
            mime: nil,
            meta: []

  @doc """
  Creates a new File document struct with the given attributes.
  """
  @spec new(map()) :: t()
  def new(attrs) do
    attrs = Map.put_new(attrs, :mime, MIME.from_path(attrs.path))
    struct!(Mulberry.Document.File, attrs)
  end

  defimpl Mulberry.Document do
    alias Mulberry.Document
    alias Mulberry.DocumentTransformer
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

    # Transform function - new unified interface
    def transform(file, transformation, opts \\ [])

    def transform(%Mulberry.Document.File{} = file, transformation, opts) do
      transformer = Keyword.get(opts, :transformer, DocumentTransformer.Default)
      transformer.transform(file, transformation, opts)
    end

    # Backward compatibility functions
    def generate_summary(file, opts \\ []) do
      transform(file, :summary, opts)
    end

    def generate_keywords(file, opts \\ []) do
      transform(file, :keywords, opts)
    end

    def generate_title(file, opts \\ []) do
      transform(file, :title, opts)
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

    def to_markdown(file, opts \\ [])

    def to_markdown(%Mulberry.Document.File{contents: contents}, opts)
        when is_binary(contents) do
      # For text files, the contents are already in a markdown-compatible format
      # Apply cleaning options if specified
      cleaned_content =
        if Keyword.get(opts, :clean_whitespace, false) do
          clean_whitespace(contents)
        else
          contents
        end

      {:ok, cleaned_content}
    end

    def to_markdown(%Mulberry.Document.File{} = file, _opts) do
      {:error, :not_loaded, file}
    end

    defp clean_whitespace(text) do
      text
      |> String.replace(~r/^[ \t]+$/m, "")
      |> String.replace(~r/\n{3,}/, "\n\n")
      |> String.split("\n")
      |> Enum.map_join("\n", &String.trim_trailing/1)
      |> String.trim()
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

        error ->
          Logger.error("#{__MODULE__}.ocr_pdf/1 error=#{inspect(error)}")
          {:error, :parse_failed, file}
      end
    end
  end
end
