defmodule Mulberry.DocumentTransformer.RedditPost do
  @moduledoc """
  Custom DocumentTransformer implementation for Reddit posts.
  Handles Reddit-specific transformation logic.
  """

  @behaviour Mulberry.DocumentTransformer

  alias Mulberry.Text

  @impl true
  def transform(post, transformation, opts \\ [])

  def transform(post, :summary, opts) do
    content = get_content_for_summary(post)

    case Text.summarize(content, opts) do
      {:ok, summary} ->
        {:ok, %{post | summary: summary}}

      {:error, error} ->
        {:error, error, post}
    end
  end

  def transform(post, :keywords, _opts) do
    # For now, return empty keywords
    # This could be enhanced with keyword extraction from title/selftext
    {:ok, %{post | keywords: []}}
  end

  def transform(post, :title, _opts) do
    # Reddit posts already have titles
    {:ok, post}
  end

  def transform(post, transformation, _opts) do
    {:error, {:unsupported_transformation, transformation}, post}
  end

  # Private helper functions

  defp get_content_for_summary(%{selftext: selftext, title: title})
       when is_binary(selftext) and selftext != "" do
    "Title: #{title}\n\n#{selftext}"
  end

  defp get_content_for_summary(%{title: title}) do
    title
  end
end
