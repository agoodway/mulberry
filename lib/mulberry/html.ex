defmodule Mulberry.HTML do
  @moduledoc false

  def to_readable_text(html_tree) do
    tags_to_br = ~r/<\/(p|div|article|h\d)/i
    html_str = Floki.raw_html(html_tree, encode: false)

    tags_to_br
    |> Regex.replace(html_str, &"\n#{&1}")
    |> Floki.parse_fragment!()
    |> Floki.text(sep: " ")
    |> String.trim()
  end

  def to_markdown(html) when is_binary(html) do
    Html2Markdown.convert(html)
  end
end
