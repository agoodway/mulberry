defmodule Mulberry do
  @moduledoc false

  @spec config(atom()) :: any()
  def config(key) do
    Application.get_env(:mulberry, key)
  end

  @spec search(module(), String.t(), pos_integer()) :: [any()]
  def search(module, query, limit \\ 3) do
    query
    |> module.search(limit)
    |> module.to_documents()
  end
end
