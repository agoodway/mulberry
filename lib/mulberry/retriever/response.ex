defmodule Mulberry.Retriever.Response do
  @moduledoc false

  @type t :: %__MODULE__{
          status: atom(),
          content: String.t()
        }

  defstruct status: nil,
            content: nil

  def default_responder(%Mulberry.Retriever.Response{status: :failed} = response),
    do: {:error, response}

  def default_responder(response), do: {:ok, response}
end
