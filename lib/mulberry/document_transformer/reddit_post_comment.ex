defmodule Mulberry.DocumentTransformer.RedditPostComment do
  @moduledoc """
  Custom DocumentTransformer implementation for Reddit post comments.
  Handles Reddit comment-specific transformation logic.
  """

  @behaviour Mulberry.DocumentTransformer

  alias Mulberry.Text

  @impl true
  def transform(doc, transformation, opts \\ [])

  def transform(%{comments: []} = doc, :summary, _opts) do
    {:error, :no_comments, doc}
  end

  def transform(doc, :summary, opts) do
    # Summarize top-level comments
    top_comments_text =
      doc.comments
      |> Enum.take(5)
      |> Enum.map_join("\n\n", fn comment ->
        truncated_body =
          if String.length(comment.body) > 200 do
            String.slice(comment.body, 0, 200) <> "..."
          else
            comment.body
          end

        "#{comment.author}: #{truncated_body}"
      end)

    case Text.summarize(top_comments_text, opts) do
      {:ok, summary} ->
        {:ok, %{doc | meta: Keyword.put(doc.meta, :summary, summary)}}

      {:error, error} ->
        {:error, error, doc}
    end
  end

  def transform(doc, :keywords, _opts) do
    # For now, return empty keywords
    {:ok, %{doc | meta: Keyword.put(doc.meta, :keywords, [])}}
  end

  def transform(doc, :title, _opts) do
    # Reddit post comments don't have titles
    {:ok, doc}
  end

  def transform(doc, transformation, _opts) do
    {:error, {:unsupported_transformation, transformation}, doc}
  end
end
