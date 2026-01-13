defmodule Mulberry.DocumentTransformer.Default do
  @moduledoc """
  Default implementation of the DocumentTransformer behavior. Handles standard
  transformations like summarization, keyword extraction, and title generation
  by delegating to the Mulberry.Text module.
  """

  @behaviour Mulberry.DocumentTransformer

  alias Mulberry.Text

  @impl true
  def transform(document, transformation, opts \\ [])

  def transform(document, :summary, opts) do
    with {:ok, text} <- get_document_text(document),
         {:ok, summary} <- Text.summarize(text, opts) do
      {:ok, Map.put(document, :summary, summary)}
    else
      {:error, :no_text_field} -> {:error, :not_loaded, document}
      {:error, reason} -> {:error, reason, document}
    end
  end

  def transform(document, :keywords, _opts) do
    case get_document_text(document) do
      {:ok, _text} ->
        # Keywords generation not yet implemented in Text module
        # For now, return empty keywords
        {:ok, Map.put(document, :keywords, [])}

      {:error, :no_text_field} ->
        {:error, :not_loaded, document}
    end
  end

  def transform(document, :title, opts) do
    # Check if document already has a title (for WebPage)
    if Map.has_key?(document, :title) && document.title do
      {:ok, document}
    else
      with {:ok, text} <- get_document_text(document),
           {:ok, title} <- Text.title(text, opts) do
        {:ok, Map.put(document, :title, title)}
      else
        {:error, :no_text_field} -> {:error, :not_loaded, document}
        {:error, reason} -> {:error, reason, document}
      end
    end
  end

  def transform(document, :extract, opts) do
    # Extract structured data using provided schema
    schema = Keyword.get(opts, :schema)

    if is_nil(schema) do
      {:error, {:missing_required_option, :schema}, document}
    else
      with {:ok, text} <- get_document_text(document),
           {:ok, extracted_data} <- Text.extract(text, opts) do
        {:ok, Map.put(document, :extracted_data, extracted_data)}
      else
        {:error, :no_text_field} -> {:error, :not_loaded, document}
        {:error, reason} -> {:error, reason, document}
      end
    end
  end

  def transform(document, transformation, _opts) do
    {:error, {:unsupported_transformation, transformation}, document}
  end

  # Helper function to extract text from document
  defp get_document_text(document) do
    cond do
      Map.has_key?(document, :markdown) && is_binary(document.markdown) ->
        {:ok, document.markdown}

      Map.has_key?(document, :content) && is_binary(document.content) ->
        {:ok, document.content}

      Map.has_key?(document, :contents) && is_binary(document.contents) ->
        {:ok, document.contents}

      true ->
        {:error, :no_text_field}
    end
  end
end
