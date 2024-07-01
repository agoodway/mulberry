defprotocol Mulberry.Document do
  alias TextChunker.Chunk

  # Loading Data

  @spec load(t, Keyword.t()) :: {:ok, t} | {:error, any(), t}
  def load(value, opts \\ [])

  # Generating Data

  @spec generate_summary(t, Keyword.t()) :: {:ok, t} | {:error, any(), t}
  def generate_summary(value, opts \\ [])

  @spec generate_keywords(t, Keyword.t()) :: {:ok, t} | {:error, any(), t}
  def generate_keywords(value, opts \\ [])

  @spec generate_title(t, Keyword.t()) :: {:ok, t} | {:error, any(), t}
  def generate_title(value, opts \\ [])

  # Fetching Data

  @spec to_text(t, Keyword.t()) :: {:ok, String.t()} | {:error, any()}
  def to_text(value, opts \\ [])

  # @spec to_audio(t, Keyword.t()) :: {:ok, any(), t} | {:error, any(), t}
  # def to_audio(value, opts)

  @spec to_tokens(t, Keyword.t()) :: {:ok, [String.t()]} | {:error, any()}
  def to_tokens(value, opts \\ [])

  @spec to_chunks(t, Keyword.t()) :: {:ok, [Chunk.t()]} | {:error, any()}
  def to_chunks(value, opts \\ [])
end
