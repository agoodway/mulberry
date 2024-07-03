defmodule Mulberry.Retriever do
  require Logger

  @callback get(String.t(), Keyword.t()) ::
              {:ok, map()} | {:error, atom()}

  def get(module, url, opts \\ []) do
    Logger.debug("#{__MODULE__}.get/2 module=#{inspect(module)} url=#{inspect(url)} opts=#{inspect(opts)}")
    module.get(url, opts)
  end
end
