defmodule Mulberry.Retriever do
  @moduledoc """
  Behavior module for HTTP content retrieval with support for multiple retriever implementations.
  Provides a unified interface for fetching web content using different strategies.
  """
  
  require Logger

  @callback get(String.t(), Keyword.t()) ::
              {:ok, map()} | {:error, atom()}

  @doc """
  Retrieves content from a URL using the specified retriever module(s).
  """
  @spec get(module() | [module()], String.t(), Keyword.t()) :: {:ok, map()} | {:error, atom()}
  def get(module, url, opts \\ [])

  def get(module, url, opts) when is_list(module) do
    Enum.reduce_while(module, nil, fn mod, _acc ->
      case get(mod, url, opts) do
        {:ok, response} -> {:halt, {:ok, response}}
        error -> {:cont, error}
      end
    end)
  end

  def get(module, url, opts) do
    Logger.debug(
      "#{__MODULE__}.get/2 module=#{inspect(module)} url=#{inspect(url)} opts=#{inspect(opts)}"
    )

    module.get(url, opts)
  end
end
