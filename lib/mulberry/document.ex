defprotocol Mulberry.Document do
  @moduledoc """
  Protocol for document processing operations including loading, generating metadata,
  and converting documents to various formats.
  """

  alias TextChunker.Chunk

  # Loading Data

  @doc """
  Loads the document content from its source (file, URL, etc.).
  """
  @spec load(t, Keyword.t()) :: {:ok, t} | {:error, any(), t}
  def load(value, opts \\ [])

  # Transformations

  @doc """
  Transforms a document using the specified transformation type.

  ## Transformation Types
    - `:summary` - Generate a summary of the document
    - `:keywords` - Extract keywords from the document
    - `:title` - Generate a title for the document

  ## Options
    - `:transformer` - Module implementing DocumentTransformer behavior (default: DocumentTransformer.Default)
    - Additional options are passed to the transformer
  """
  @spec transform(t, atom(), Keyword.t()) :: {:ok, t} | {:error, any(), t}
  def transform(value, transformation, opts \\ [])

  # Generating Data (Backward Compatibility)

  @doc """
  Generates a summary of the document content using AI.

  This function is maintained for backward compatibility.
  Internally delegates to `transform(doc, :summary, opts)`.
  """
  @spec generate_summary(t, Keyword.t()) :: {:ok, t} | {:error, any(), t}
  def generate_summary(value, opts \\ [])

  @doc """
  Extracts keywords from the document content.

  This function is maintained for backward compatibility.
  Internally delegates to `transform(doc, :keywords, opts)`.
  """
  @spec generate_keywords(t, Keyword.t()) :: {:ok, t} | {:error, any(), t}
  def generate_keywords(value, opts \\ [])

  @doc """
  Generates a title for the document based on its content.

  This function is maintained for backward compatibility.
  Internally delegates to `transform(doc, :title, opts)`.
  """
  @spec generate_title(t, Keyword.t()) :: {:ok, t} | {:error, any(), t}
  def generate_title(value, opts \\ [])

  # Fetching Data

  @doc """
  Converts the document to plain text format.
  """
  @spec to_text(t, Keyword.t()) :: {:ok, String.t()} | {:error, any()}
  def to_text(value, opts \\ [])

  # @spec to_audio(t, Keyword.t()) :: {:ok, any(), t} | {:error, any(), t}
  # def to_audio(value, opts)

  @doc """
  Tokenizes the document content into a list of tokens.
  """
  @spec to_tokens(t, Keyword.t()) :: {:ok, [String.t()]} | {:error, any()}
  def to_tokens(value, opts \\ [])

  @doc """
  Splits the document into semantic chunks for processing.
  """
  @spec to_chunks(t, Keyword.t()) :: {:ok, [Chunk.t()]} | {:error, any()}
  def to_chunks(value, opts \\ [])
end
