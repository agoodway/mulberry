defmodule Mulberry.HTML do
  @moduledoc false

  @doc """
  Converts an HTML tree to readable plain text with line breaks.
  """
  @spec to_readable_text(Floki.html_tree()) :: String.t()
  def to_readable_text(html_tree) do
    html_tree
    |> process_tree()
    |> format_final_output()
  end
  
  defp process_tree([]), do: []
  defp process_tree([item | rest]) do
    [process_item(item) | process_tree(rest)]
  end
  defp process_tree(item), do: [process_item(item)]
  
  defp process_item({tag, _attrs, children}) when is_binary(tag) do
    # Process children to get their formatted items
    child_items = process_tree(children)
    
    # For div and other containers, we need to preserve the child structure
    # to ensure proper spacing between different types of elements
    content = case tag do
      tag when tag in ["div"] ->
        # Special handling for div to maintain spacing between child elements
        format_div_content(child_items)
      _ ->
        # For other elements, use normal formatting
        child_items
        |> format_final_output()
        |> String.trim_trailing("\n")
    end
    
    case tag do
      # Block elements
      tag when tag in ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "article", "section", "custom-element"] ->
        {:block, content}
        
      # List containers
      tag when tag in ["ul", "ol"] ->
        {:list, content}
        
      # List items
      "li" ->
        {:list_item, content}
        
      # Line breaks
      "br" ->
        {:br}
        
      # Inline elements
      _ ->
        {:inline, content}
    end
  end
  
  defp process_item(text) when is_binary(text), do: {:text, text}
  defp process_item(_), do: {:text, ""}
  
  defp format_final_output(items) when is_list(items) do
    items
    |> Enum.reduce({[], nil}, fn item, {acc, prev} ->
      formatted = format_item(item, prev)
      {[formatted | acc], item}
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.join()
  end
  defp format_final_output(text) when is_binary(text), do: text
  
  defp format_item({:text, text}, _prev), do: text
  
  defp format_item({:inline, content}, _prev), do: content
  
  defp format_item({:block, content}, prev) do
    base = if content == "", do: "\n", else: content <> "\n"
    
    # Add extra newline if previous was also a block
    case prev do
      {:block, _} -> "\n" <> base
      _ -> base
    end
  end
  
  defp format_item({:list, content}, prev) do
    base = content <> "\n\n"
    
    # Add extra newline if previous was a block
    case prev do
      {:block, _} -> "\n" <> base
      _ -> base
    end
  end
  
  defp format_item({:list_item, content}, _prev) do
    content <> "\n"
  end
  
  defp format_item({:br}, _prev), do: "\n"
  
  defp format_div_content(items) do
    # Special formatting for div content to ensure proper spacing
    items
    |> Enum.reduce({[], nil}, fn item, {acc, prev} ->
      formatted = case {prev, item} do
        # Block followed by inline needs double newline
        {{:block, _}, {:inline, content}} -> "\n" <> content
        # Block followed by text needs double newline
        {{:block, _}, {:text, text}} -> "\n" <> text
        # Otherwise use normal formatting
        _ -> format_item(item, prev)
      end
      {[formatted | acc], item}
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.join()
    |> String.trim_trailing("\n")
  end

  @doc """
  Converts HTML string to Markdown format.
  """
  @spec to_markdown(String.t()) :: {:ok, String.t()} | {:error, any()}
  def to_markdown(html) when is_binary(html) do
    case Html2Markdown.convert(html) do
      markdown when is_binary(markdown) -> {:ok, markdown}
      error -> {:error, error}
    end
  end
end