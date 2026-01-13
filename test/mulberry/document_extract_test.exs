defmodule Mulberry.DocumentExtractTest do
  use ExUnit.Case, async: true
  use Mimic
  alias Mulberry.Document
  alias Mulberry.Document.WebPage
  alias Mulberry.Document.File
  alias Mulberry.Text

  describe "transform/3 with :extract" do
    test "extracts structured data from WebPage document" do
      # Create a loaded WebPage document
      web_page = %WebPage{
        url: "https://example.com",
        markdown: "John Smith is a 32-year-old software engineer at TechCorp.",
        content: "<html>...</html>"
      }

      # Mock Text.extract
      expected_data = [
        %{
          "person_name" => "John Smith",
          "age" => 32,
          "occupation" => "software engineer",
          "company" => "TechCorp"
        }
      ]

      stub(Text, :extract, fn text, opts ->
        assert text == web_page.markdown

        assert opts[:schema] == %{
                 type: "object",
                 properties: %{
                   person_name: %{type: "string"},
                   age: %{type: "number"},
                   occupation: %{type: "string"},
                   company: %{type: "string"}
                 }
               }

        {:ok, expected_data}
      end)

      schema = %{
        type: "object",
        properties: %{
          person_name: %{type: "string"},
          age: %{type: "number"},
          occupation: %{type: "string"},
          company: %{type: "string"}
        }
      }

      assert {:ok, updated_page} = Document.transform(web_page, :extract, schema: schema)
      assert updated_page.extracted_data == expected_data
    end

    test "extracts structured data from File document" do
      # Create a loaded File document
      file = %File{
        path: "/path/to/document.txt",
        contents: "Jane Doe, aged 28, works as a data scientist at DataCo.",
        mime: "text/plain"
      }

      # Mock Text.extract
      expected_data = [
        %{
          "person_name" => "Jane Doe",
          "age" => 28,
          "occupation" => "data scientist",
          "company" => "DataCo"
        }
      ]

      stub(Text, :extract, fn text, _opts ->
        assert text == file.contents
        {:ok, expected_data}
      end)

      schema = %{
        type: "object",
        properties: %{
          person_name: %{type: "string"},
          age: %{type: "number"},
          occupation: %{type: "string"},
          company: %{type: "string"}
        }
      }

      assert {:ok, updated_file} = Document.transform(file, :extract, schema: schema)
      assert updated_file.extracted_data == expected_data
    end

    test "returns error when schema is not provided" do
      web_page = %WebPage{
        url: "https://example.com",
        markdown: "Some content"
      }

      assert {:error, {:missing_required_option, :schema}, ^web_page} =
               Document.transform(web_page, :extract)
    end

    test "returns error when document is not loaded" do
      web_page = %WebPage{
        url: "https://example.com"
        # No content or markdown
      }

      schema = %{type: "object", properties: %{}}

      assert {:error, :not_loaded, ^web_page} =
               Document.transform(web_page, :extract, schema: schema)
    end

    test "passes through extraction errors" do
      web_page = %WebPage{
        url: "https://example.com",
        markdown: "Some content"
      }

      stub(Text, :extract, fn _text, _opts ->
        {:error, :extraction_failed}
      end)

      schema = %{type: "object", properties: %{}}

      assert {:error, :extraction_failed, ^web_page} =
               Document.transform(web_page, :extract, schema: schema)
    end

    test "uses custom transformer when provided" do
      defmodule CustomTransformer do
        @behaviour Mulberry.DocumentTransformer

        def transform(document, :extract, _opts) do
          # Custom extraction logic
          {:ok, Map.put(document, :extracted_data, [%{"custom" => true}])}
        end

        def transform(document, _transformation, _opts) do
          {:error, :unsupported, document}
        end
      end

      web_page = %WebPage{
        url: "https://example.com",
        markdown: "Content"
      }

      schema = %{type: "object", properties: %{}}

      assert {:ok, updated_page} =
               Document.transform(web_page, :extract,
                 schema: schema,
                 transformer: CustomTransformer
               )

      assert updated_page.extracted_data == [%{"custom" => true}]
    end

    test "passes additional options to Text.extract" do
      web_page = %WebPage{
        url: "https://example.com",
        markdown: "Content"
      }

      stub(Text, :extract, fn _text, opts ->
        assert opts[:verbose] == true
        assert opts[:provider] == :openai
        assert opts[:temperature] == 0.0
        {:ok, []}
      end)

      schema = %{type: "object", properties: %{}}

      Document.transform(web_page, :extract,
        schema: schema,
        verbose: true,
        provider: :openai,
        temperature: 0.0
      )
    end
  end
end
