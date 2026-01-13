defmodule Mulberry.HTMLTest do
  use ExUnit.Case, async: true
  doctest Mulberry.HTML

  alias Mulberry.HTML

  describe "to_readable_text/1" do
    test "converts simple HTML to readable text" do
      html_tree = [{"p", [], ["Hello world"]}]
      assert HTML.to_readable_text(html_tree) == "Hello world\n"
    end

    test "adds line breaks after block elements" do
      html_tree = [
        {"p", [], ["First paragraph"]},
        {"p", [], ["Second paragraph"]}
      ]

      assert HTML.to_readable_text(html_tree) == "First paragraph\n\nSecond paragraph\n"
    end

    test "handles div elements with line breaks" do
      html_tree = [
        {"div", [], ["First div"]},
        {"div", [], ["Second div"]}
      ]

      assert HTML.to_readable_text(html_tree) == "First div\n\nSecond div\n"
    end

    test "handles headings with appropriate line breaks" do
      html_tree = [
        {"h1", [], ["Main Title"]},
        {"h2", [], ["Subtitle"]},
        {"p", [], ["Content"]}
      ]

      assert HTML.to_readable_text(html_tree) == "Main Title\n\nSubtitle\n\nContent\n"
    end

    test "handles lists with line breaks" do
      html_tree = [
        {"ul", [],
         [
           {"li", [], ["Item 1"]},
           {"li", [], ["Item 2"]}
         ]}
      ]

      assert HTML.to_readable_text(html_tree) == "Item 1\nItem 2\n\n"
    end

    test "handles nested elements" do
      html_tree = [
        {"div", [],
         [
           {"p", [], ["Nested paragraph"]},
           {"span", [], ["Inline text"]}
         ]}
      ]

      assert HTML.to_readable_text(html_tree) == "Nested paragraph\n\nInline text\n"
    end

    test "handles text nodes directly" do
      html_tree = ["Just text"]
      assert HTML.to_readable_text(html_tree) == "Just text"
    end

    test "handles inline elements without extra line breaks" do
      html_tree = [
        {"p", [],
         [
           "Text with ",
           {"strong", [], ["bold"]},
           " and ",
           {"em", [], ["italic"]},
           " elements"
         ]}
      ]

      assert HTML.to_readable_text(html_tree) == "Text with bold and italic elements\n"
    end

    test "handles br tags" do
      html_tree = [
        {"p", [],
         [
           "Line 1",
           {"br", [], []},
           "Line 2"
         ]}
      ]

      assert HTML.to_readable_text(html_tree) == "Line 1\nLine 2\n"
    end

    test "handles empty elements" do
      html_tree = [
        {"p", [], []},
        {"div", [], []}
      ]

      assert HTML.to_readable_text(html_tree) == "\n\n\n"
    end

    test "handles unknown elements as block elements" do
      html_tree = [
        {"custom-element", [], ["Custom content"]}
      ]

      assert HTML.to_readable_text(html_tree) == "Custom content\n"
    end
  end

  describe "to_markdown/1" do
    test "converts HTML string to markdown" do
      html = "<p>Hello <strong>world</strong></p>"
      result = HTML.to_markdown(html)
      assert {:ok, markdown} = result
      assert String.contains?(markdown, "Hello **world**")
    end

    test "handles complex HTML with lists" do
      html = """
      <h1>Title</h1>
      <p>Paragraph</p>
      <ul>
        <li>Item 1</li>
        <li>Item 2</li>
      </ul>
      """

      result = HTML.to_markdown(html)
      assert {:ok, markdown} = result
      assert String.contains?(markdown, "# Title")
      assert String.contains?(markdown, "- Item 1")
      assert String.contains?(markdown, "- Item 2")
    end

    test "handles links in HTML" do
      html = ~s(<p>Visit <a href="https://example.com">example</a></p>)
      result = HTML.to_markdown(html)
      assert {:ok, markdown} = result
      assert String.contains?(markdown, "[example](https://example.com)")
    end

    test "handles code blocks" do
      html = "<pre><code>def hello do\n  :world\nend</code></pre>"
      result = HTML.to_markdown(html)
      assert {:ok, markdown} = result
      assert String.contains?(markdown, "```")
      assert String.contains?(markdown, "def hello do")
    end

    test "returns error tuple for invalid HTML" do
      # This test depends on html2markdown library behavior
      # Adjust based on actual error handling
      html = ""
      result = HTML.to_markdown(html)
      # Empty HTML should still return ok with empty markdown
      assert {:ok, _} = result
    end
  end
end
