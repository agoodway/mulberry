defmodule Mulberry.Search.Behaviour do
  @moduledoc false
  alias Mulberry.Document.WebPage
  alias Mulberry.Document.File

  @callback search(binary(), pos_integer(), keyword()) ::
              {:ok, map()} | {:error, binary()}
  @callback to_documents(any()) ::
              {:ok, [WebPage.t() | File.t()]} | {:error, atom()}
end
