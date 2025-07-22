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

  # Generating Data

  @doc """
  Generates a summary of the document content using AI.
  """
  @spec generate_summary(t, Keyword.t()) :: {:ok, t} | {:error, any(), t}
  def generate_summary(value, opts \\ [])

  @doc """
  Extracts keywords from the document content.
  """
  @spec generate_keywords(t, Keyword.t()) :: {:ok, t} | {:error, any(), t}
  def generate_keywords(value, opts \\ [])

  @doc """
  Generates a title for the document based on its content.
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
