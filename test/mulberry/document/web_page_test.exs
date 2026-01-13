defmodule Mulberry.Document.WebPageTest do
  use ExUnit.Case, async: false
  use Mimic
  doctest Mulberry.Document.WebPage

  setup :set_mimic_global

  alias Mulberry.Document.WebPage
  alias Mulberry.Retriever

  describe "new/1" do
    test "creates a new WebPage struct with URL" do
      url = Faker.Internet.url()
      attrs = %{url: url}

      web_page = WebPage.new(attrs)

      assert %WebPage{url: ^url} = web_page
      assert web_page.title == nil
      assert web_page.summary == nil
    end

    test "creates WebPage with all attributes" do
      attrs = %{
        url: Faker.Internet.url(),
        title: Faker.Lorem.sentence(),
        summary: Faker.Lorem.paragraph(),
        content: Faker.Lorem.paragraphs(3) |> Enum.join("\n\n"),
        keywords: Faker.Lorem.words(5)
      }

      web_page = WebPage.new(attrs)

      assert web_page.url == attrs.url
      assert web_page.title == attrs.title
      assert web_page.summary == attrs.summary
      assert web_page.content == attrs.content
      assert web_page.keywords == attrs.keywords
    end
  end

  describe "load/2" do
    test "loads web page content successfully" do
      url = Faker.Internet.url()
      html_content = "<html><body><p>#{Faker.Lorem.paragraph()}</p></body></html>"
      web_page = %WebPage{url: url}

      expect(Mulberry.Retriever, :get, fn module, ^url ->
        assert module == Retriever.Req
        {:ok, %Mulberry.Retriever.Response{status: :ok, content: html_content}}
      end)

      {:ok, result} = Mulberry.Document.load(web_page)

      assert %WebPage{url: ^url, content: ^html_content} = result
      assert result.markdown != nil
    end

    test "uses custom retrievers from options" do
      url = Faker.Internet.url()
      web_page = %WebPage{url: url}

      expect(Mulberry.Retriever, :get, fn Retriever.ScrapingBee, ^url ->
        {:ok, %Mulberry.Retriever.Response{status: :ok, content: "<p>Content</p>"}}
      end)

      {:ok, _result} = Mulberry.Document.load(web_page, retriever: Retriever.ScrapingBee)
    end

    test "handles retriever error" do
      url = Faker.Internet.url()
      web_page = %WebPage{url: url}

      expect(Mulberry.Retriever, :get, fn Mulberry.Retriever.Req, ^url ->
        {:error, %Mulberry.Retriever.Response{status: :failed, content: nil}}
      end)

      assert {:error, response, ^web_page} = Mulberry.Document.load(web_page)
      assert %Mulberry.Retriever.Response{status: :failed} = response
    end

    test "extracts text from HTML response" do
      url = Faker.Internet.url()
      web_page = %WebPage{url: url}

      html = """
      <html>
        <body>
          <h1>Title</h1>
          <p>First paragraph</p>
          <p>Second paragraph</p>
        </body>
      </html>
      """

      expect(Mulberry.Retriever, :get, fn Mulberry.Retriever.Req, ^url ->
        {:ok, %Mulberry.Retriever.Response{status: :ok, content: html}}
      end)

      {:ok, result} = Mulberry.Document.load(web_page)

      assert result.content =~ "Title"
      assert result.content =~ "First paragraph"
      assert result.content =~ "Second paragraph"
    end
  end

  describe "Document protocol implementation" do
    test "generate_summary/2" do
      markdown = Faker.Lorem.paragraphs(3) |> Enum.join("\n\n")

      web_page = %WebPage{
        url: Faker.Internet.url(),
        markdown: markdown
      }

      # Create a mock LLM to bypass Config.get_llm
      mock_llm = %{id: "test-llm"}

      # Mock the SummarizeDocumentChain since Text.summarize uses it
      expect(Mulberry.Chains.SummarizeDocumentChain, :new, fn config ->
        assert config.llm == mock_llm
        {:ok, %{chain: "fake"}}
      end)

      expect(Mulberry.Chains.SummarizeDocumentChain, :summarize, fn _chain, _doc, _opts ->
        {:ok, "Generated summary"}
      end)

      result = Mulberry.Document.generate_summary(web_page, llm: mock_llm)
      assert {:ok, %WebPage{summary: summary}} = result
      assert summary == "Generated summary"
    end

    test "generate_keywords/2" do
      web_page = %WebPage{
        url: Faker.Internet.url(),
        markdown: Faker.Lorem.paragraphs(2) |> Enum.join("\n\n")
      }

      assert {:ok, %WebPage{keywords: []}} = Mulberry.Document.generate_keywords(web_page)
    end

    test "generate_title/2" do
      markdown = Faker.Lorem.paragraph()

      web_page = %WebPage{
        url: Faker.Internet.url(),
        markdown: markdown
      }

      # Create a mock LLM struct to bypass Config.get_llm
      mock_llm = %LangChain.ChatModels.ChatOpenAI{
        model: "gpt-3.5-turbo",
        api_key: "fake-key"
      }

      # Create a mock chain
      mock_chain = %LangChain.Chains.LLMChain{
        llm: mock_llm,
        messages: []
      }

      # Mock the chain creation
      stub(LangChain.Chains.LLMChain, :new!, fn _attrs ->
        mock_chain
      end)

      stub(LangChain.Chains.LLMChain, :add_messages, fn chain, _messages ->
        chain
      end)

      # Mock the LLMChain.run to return our title
      expect(LangChain.Chains.LLMChain, :run, fn _chain, _opts ->
        {:ok, mock_chain, %LangChain.Message{role: :assistant, content: "Generated Title"}}
      end)

      result = Mulberry.Document.generate_title(web_page, llm: mock_llm)
      assert {:ok, %WebPage{title: title}} = result
      assert title == "Generated Title"
    end

    test "generate_title/2 returns existing title" do
      web_page = %WebPage{
        url: Faker.Internet.url(),
        markdown: "content",
        title: "Existing Title"
      }

      assert {:ok, %WebPage{title: "Existing Title"}} =
               Mulberry.Document.generate_title(web_page)
    end

    test "to_text/2 returns markdown content" do
      markdown = Faker.Lorem.paragraphs(2) |> Enum.join("\n\n")

      web_page = %WebPage{
        url: Faker.Internet.url(),
        markdown: markdown
      }

      assert {:ok, ^markdown} = Mulberry.Document.to_text(web_page)
    end

    test "to_text/2 returns error when not loaded" do
      web_page = %WebPage{url: Faker.Internet.url()}

      assert {:error, :not_loaded} = Mulberry.Document.to_text(web_page)
    end

    test "to_tokens/2" do
      markdown = Faker.Lorem.paragraph()
      web_page = %WebPage{markdown: markdown}

      expect(Mulberry.Text, :tokens, fn ^markdown ->
        {:ok, ["token1", "token2", "token3"]}
      end)

      assert {:ok, tokens} = Mulberry.Document.to_tokens(web_page)
      assert tokens == ["token1", "token2", "token3"]
    end

    test "to_tokens/2 returns error when not loaded" do
      web_page = %WebPage{url: Faker.Internet.url()}

      assert {:error, :not_loaded} = Mulberry.Document.to_tokens(web_page)
    end

    test "to_chunks/2" do
      markdown = Faker.Lorem.paragraphs(5) |> Enum.join("\n\n")
      web_page = %WebPage{markdown: markdown}

      expect(Mulberry.Text, :split, fn ^markdown ->
        ["chunk1", "chunk2", "chunk3"]
      end)

      assert {:ok, ["chunk1", "chunk2", "chunk3"]} = Mulberry.Document.to_chunks(web_page)
    end

    test "to_chunks/2 returns error when not loaded" do
      web_page = %WebPage{url: Faker.Internet.url()}

      assert {:error, :not_loaded} = Mulberry.Document.to_chunks(web_page)
    end
  end

  describe "error handling" do
    test "handles LLM errors in generate_summary" do
      markdown = "content"
      web_page = %WebPage{markdown: markdown}

      # Create a mock LLM to bypass Config.get_llm
      mock_llm = %{id: "test-llm"}

      # Mock the SummarizeDocumentChain to return error
      expect(Mulberry.Chains.SummarizeDocumentChain, :new, fn _config ->
        {:ok, %{chain: "fake"}}
      end)

      expect(Mulberry.Chains.SummarizeDocumentChain, :summarize, fn _chain, _doc, _opts ->
        {:error, "API error"}
      end)

      assert {:error, "API error", ^web_page} =
               Mulberry.Document.generate_summary(web_page, llm: mock_llm)
    end

    test "handles empty markdown gracefully" do
      web_page = %WebPage{url: Faker.Internet.url(), markdown: ""}

      # Should not crash
      assert {:ok, ""} = Mulberry.Document.to_text(web_page)

      expect(Mulberry.Text, :split, fn "" -> [""] end)
      assert {:ok, [""]} = Mulberry.Document.to_chunks(web_page)
    end
  end
end
