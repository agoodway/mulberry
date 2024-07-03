defmodule Mulberry.Retriever.Response do
  @moduledoc false

  @type t :: %__MODULE__{
          status: atom(),
          content: String.t()
        }

  defstruct status: nil,
            content: nil
end
