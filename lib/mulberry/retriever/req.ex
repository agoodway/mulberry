defmodule Mulberry.Retriever.Req do
  @behaviour Mulberry.Retriever

  def get(url, opts \\ []) do
    params = Keyword.get(opts, :params, %{})
    headers = Keyword.get(opts, :headers, %{})

    case Req.get(url, headers: headers, params: params) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, %Mulberry.Retriever.Response{status: :ok, content: body}}

      _ ->
        {:error, :failed}
    end
  end
end
