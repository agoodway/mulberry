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
          extracted_data: list(map()) | nil,
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
            extracted_data: nil,
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

    def to_markdown(web_page, opts \\ [])

    def to_markdown(%WebPage{markdown: markdown}, opts) when is_binary(markdown) do
      cleaned_markdown =
        if Keyword.get(opts, :clean_whitespace, false) do
          clean_whitespace(markdown)
        else
          markdown
        end

      final_markdown =
        if Keyword.get(opts, :remove_empty_sections, false) do
          remove_empty_sections(cleaned_markdown)
        else
          cleaned_markdown
        end

      {:ok, final_markdown}
    end

    def to_markdown(%WebPage{}, _opts) do
      {:error, :not_loaded}
    end

    # Private helpers for markdown cleaning

    defp clean_whitespace(markdown) do
      markdown
      # Remove lines with only whitespace
      |> String.replace(~r/^[ \t]+$/m, "")
      # Collapse more than 2 consecutive newlines to 2
      |> String.replace(~r/\n{3,}/, "\n\n")
      # Trim trailing whitespace from each line
      |> String.split("\n")
      |> Enum.map_join("\n", &String.trim_trailing/1)
      # Trim leading and trailing whitespace from the whole document
      |> String.trim()
    end

    defp remove_empty_sections(markdown) do
      # Split into sections by headers
      # A section is considered empty if it has < 50 chars of non-whitespace content
      lines = String.split(markdown, "\n")

      {processed_lines, last_section, last_content} =
        Enum.reduce(lines, {[], nil, []}, &process_section_line/2)

      # Process the last section
      final_lines = finalize_sections(processed_lines, last_section, last_content)

      Enum.join(final_lines, "\n")
    end

    defp process_section_line(line, {acc, current_header, section_content}) do
      if String.match?(line, ~r/^\#{1,6}\s+/) do
        new_acc = maybe_add_previous_section(acc, current_header, section_content)
        {new_acc, line, []}
      else
        {acc, current_header, section_content ++ [line]}
      end
    end

    defp maybe_add_previous_section(acc, nil, section_content), do: acc ++ section_content

    defp maybe_add_previous_section(acc, header, section_content) do
      if section_has_content?(section_content) do
        acc ++ [header | section_content]
      else
        acc
      end
    end

    defp finalize_sections(processed_lines, nil, last_content) do
      processed_lines ++ last_content
    end

    defp finalize_sections(processed_lines, last_section, last_content) do
      if section_has_content?(last_content) do
        processed_lines ++ [last_section | last_content]
      else
        processed_lines
      end
    end

    defp section_has_content?(content) do
      content
      |> Enum.join("")
      |> String.replace(~r/\s+/, "")
      |> String.length()
      |> Kernel.>=(50)
    end
  end
end
