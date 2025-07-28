defmodule Mulberry.Search.Behaviour do
  @moduledoc false
  alias Mulberry.Document.File
  alias Mulberry.Document.WebPage

  @callback search(binary(), pos_integer(), keyword()) ::
              {:ok, map()} | {:error, binary()}
  @callback to_documents(any()) ::
              {:ok, [WebPage.t() | File.t()]} | {:error, atom()}
end
