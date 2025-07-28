defmodule Mulberry.DocumentTransformer do
  @moduledoc """
  Behavior for transforming documents. Provides a unified interface for applying
  various transformations to documents such as summarization, keyword extraction,
  and title generation.
  """

  @type transformation :: :summary | :keywords | :title | atom()
  @type document :: struct()
  @type opts :: Keyword.t()

  @doc """
  Transforms a document based on the specified transformation type.

  ## Parameters
    - `document` - The document struct to transform
    - `transformation` - The type of transformation to apply (e.g., :summary, :keywords, :title)
    - `opts` - Options to pass to the transformation

  ## Returns
    - `{:ok, transformed_document}` - Successfully transformed document
    - `{:error, reason, document}` - Transformation failed with reason
  """
  @callback transform(document, transformation, opts) ::
              {:ok, document} | {:error, any(), document}
end
