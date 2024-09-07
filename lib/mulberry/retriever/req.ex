defmodule Mulberry.Retriever.Req do
  require Logger
  @behaviour Mulberry.Retriever

  @impl true
  def get(url, opts \\ []) do
    params = Keyword.get(opts, :params, %{})
    headers = Keyword.get(opts, :headers, %{})

    responder =
      Keyword.get(opts, :responder, &Mulberry.Retriever.Response.default_responder/1)

    case Req.get(url, headers: headers, params: params) do
      {:ok, %Req.Response{status: status, body: body}} when status < 400 ->
        %Mulberry.Retriever.Response{status: :ok, content: body}

      error ->
        Logger.error("Mulberry - Failed to get #{url}: #{inspect(error)}")
        %Mulberry.Retriever.Response{status: :failed, content: nil}
    end
    |> responder.()
  end
end
