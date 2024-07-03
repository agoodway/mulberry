defmodule Mulberry.Retriever do
  @callback get(String.t(), Keyword.t()) ::
              {:ok, map()} | {:error, atom()}

  def get(module, url, opts \\ []) do
    module.get(url, opts)
  end
end
