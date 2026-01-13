defmodule Mulberry.DocumentTransformerTest do
  use ExUnit.Case, async: true

  alias Mulberry.Document.WebPage
  alias Mulberry.DocumentTransformer

  describe "DocumentTransformer behavior" do
    test "transform/3 works with default transformer" do
      doc =
        WebPage.new(%{
          url: "https://example.com",
          markdown: nil,
          content: nil
        })

      # Test that transform delegates correctly - no content loaded
      assert {:error, :not_loaded, _} = DocumentTransformer.Default.transform(doc, :summary, [])

      # Test with loaded content
      loaded_doc = %{doc | content: "Test content"}
      assert {:ok, transformed} = DocumentTransformer.Default.transform(loaded_doc, :keywords, [])
      assert transformed.keywords == []
    end

    test "transform/3 handles unsupported transformations" do
      doc =
        WebPage.new(%{
          url: "https://example.com",
          content: "Test content"
        })

      assert {:error, {:unsupported_transformation, :unknown}, ^doc} =
               DocumentTransformer.Default.transform(doc, :unknown, [])
    end
  end

  describe "Document protocol integration" do
    test "generate_* functions delegate to transform/3" do
      doc =
        WebPage.new(%{
          url: "https://example.com",
          content: "Test content",
          markdown: "Test content"
        })

      # Test that the backward compatibility functions work
      # Keywords generation returns empty list by default
      assert {:ok, doc_with_keywords} = Mulberry.Document.generate_keywords(doc)
      assert doc_with_keywords.keywords == []

      # Title generation for WebPage checks if title already exists
      doc_with_title = %{doc | title: "Existing Title"}
      assert {:ok, unchanged} = Mulberry.Document.generate_title(doc_with_title)
      assert unchanged.title == "Existing Title"
    end

    test "transform/3 can use custom transformers" do
      doc =
        WebPage.new(%{
          url: "https://example.com",
          content: "Test content"
        })

      # Using a specific transformer
      result =
        Mulberry.Document.transform(doc, :keywords, transformer: DocumentTransformer.Default)

      assert {:ok, transformed} = result
      assert transformed.keywords == []
    end
  end
end
