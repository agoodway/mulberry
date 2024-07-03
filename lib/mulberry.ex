defmodule Mulberry do
  @moduledoc false

  alias Mulberry.Document
  alias Mulberry.Document.WebPage
  alias Mulberry.Document.File
  alias Flamel.Chain

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

  def summarize(uri, opts \\ []) do
    if String.starts_with?(uri, "http") do
      WebPage.new(%{url: uri})
    else
      File.new(%{path: uri})
    end
    |> Chain.new()
    |> Chain.apply(&Document.load(&1, opts))
    |> Chain.apply(&Document.generate_summary/1)
    |> Chain.to_value()
    |> Document.to_text()
  end
end
