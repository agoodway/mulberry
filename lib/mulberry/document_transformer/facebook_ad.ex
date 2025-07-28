defmodule Mulberry.DocumentTransformer.FacebookAd do
  @moduledoc """
  Custom DocumentTransformer implementation for Facebook ads.
  Handles Facebook ad-specific transformation logic.
  """

  @behaviour Mulberry.DocumentTransformer

  alias Mulberry.Text

  @title_truncation_limit 50

  @impl true
  def transform(ad, transformation, opts \\ [])

  def transform(ad, :summary, opts) do
    content = get_content_for_summary(ad)
    
    case Text.summarize(content, opts) do
      {:ok, summary} ->
        {:ok, %{ad | summary: summary}}
        
      {:error, error} ->
        {:error, error, ad}
    end
  end

  def transform(ad, :keywords, _opts) do
    # For now, return empty keywords
    # This could be enhanced with keyword extraction from ad content
    {:ok, %{ad | keywords: []}}
  end

  def transform(ad, :title, _opts) do
    # Facebook ads may already have titles or we can generate from content
    if ad.title do
      {:ok, ad}
    else
      # Generate title from page name and ad content
      title = generate_ad_title(ad)
      {:ok, %{ad | title: title}}
    end
  end

  def transform(ad, transformation, _opts) do
    {:error, {:unsupported_transformation, transformation}, ad}
  end

  # Private helper functions
  
  defp get_content_for_summary(ad) do
    parts = [
      if(ad.page_name, do: "Advertiser: #{ad.page_name}", else: nil),
      if(ad.title, do: "Title: #{ad.title}", else: nil),
      if(ad.body_text, do: "Content: #{ad.body_text}", else: nil),
      if(ad.link_description, do: "Description: #{ad.link_description}", else: nil),
      if(ad.cta_text, do: "Call to Action: #{ad.cta_text}", else: nil)
    ]
    
    parts
    |> Enum.filter(& &1)
    |> Enum.join("\n\n")
  end

  defp generate_ad_title(%{page_name: page_name, body_text: body_text}) 
       when is_binary(page_name) and is_binary(body_text) do
    # Take first sentence or first 50 chars of body text
    preview = body_text
              |> String.split(~r/[.!?]/, parts: 2)
              |> List.first()
              |> String.slice(0, @title_truncation_limit)
    
    "#{page_name}: #{preview}"
  end
  
  defp generate_ad_title(%{page_name: page_name}) when is_binary(page_name) do
    "Ad by #{page_name}"
  end
  
  defp generate_ad_title(_), do: "Facebook Ad"
end