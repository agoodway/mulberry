defmodule Mulberry.Document.WebPageTest do
  use ExUnit.Case, async: true
  use Mimic
  import ExUnit.CaptureLog
  doctest Mulberry.Document.WebPage

  alias Mulberry.Document.WebPage
  alias Mulberry.Retriever
  alias Mulberry.Retriever.Response
  alias Mulberry.HTML
  alias Mulberry.Text
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.Chains.LLMChain
  alias LangChain.Message

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
      
      expect(Retriever, :get, fn modules, ^url, opts -> 
        assert modules == [Retriever.Req, Retriever.Playwright]
        assert opts[:responder]
        {:ok, %{body: html_content, status: 200}}
      end)
      
      result = WebPage.load(web_page)
      
      assert %WebPage{url: ^url, content: content} = result
      assert is_binary(content)
      assert content != ""
    end

    test "uses custom retrievers from options" do
      url = Faker.Internet.url()
      web_page = %WebPage{url: url}
      custom_retrievers = [Retriever.ScrapingBee]
      
      expect(Retriever, :get, fn ^custom_retrievers, ^url, _ -> 
        {:ok, %{body: "<p>Content</p>", status: 200}}
      end)
      
      WebPage.load(web_page, retrievers: custom_retrievers)
    end

    test "handles retriever error" do
      url = Faker.Internet.url()
      web_page = %WebPage{url: url}
      
      expect(Retriever, :get, fn _, ^url, _ -> 
        {:error, :connection_failed}
      end)
      
      assert {:error, :connection_failed} = WebPage.load(web_page)
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
      
      expect(Retriever, :get, fn _, ^url, _ -> 
        {:ok, %{body: html, status: 200}}
      end)
      
      result = WebPage.load(web_page)
      
      assert result.content =~ "Title"
      assert result.content =~ "First paragraph"
      assert result.content =~ "Second paragraph"
    end
  end

  describe "Document protocol implementation" do
    setup do
      # Common mocks for LLM operations
      expect(ChatOpenAI, :new!, fn [] -> %ChatOpenAI{} end)
      expect(LLMChain, :new!, fn _ -> %LLMChain{} end)
      expect(LLMChain, :add_messages, fn chain, _ -> chain end)
      :ok
    end

    test "generate_summary/2" do
      markdown = Faker.Lorem.paragraphs(3) |> Enum.join("\n\n")
      web_page = %WebPage{
        url: Faker.Internet.url(),
        markdown: markdown
      }
      
      expect(Text, :summarize, fn ^markdown -> 
        {:ok, "Generated summary"}
      end)
      
      assert {:ok, %WebPage{summary: "Generated summary"}} = 
        Mulberry.Document.generate_summary(web_page)
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
      
      expect(Text, :title, fn ^markdown -> 
        {:ok, "Generated Title"}
      end)
      
      assert {:ok, %WebPage{title: "Generated Title"}} = 
        Mulberry.Document.generate_title(web_page)
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
      
      expect(Text, :tokens, fn ^markdown -> 
        {:ok, ["token1", "token2", "token3"]}
      end)
      
      assert {:ok, ["token1", "token2", "token3"]} = Mulberry.Document.to_tokens(web_page)
    end

    test "to_tokens/2 returns error when not loaded" do
      web_page = %WebPage{url: Faker.Internet.url()}
      
      assert {:error, :not_loaded} = Mulberry.Document.to_tokens(web_page)
    end

    test "to_chunks/2" do
      markdown = Faker.Lorem.paragraphs(5) |> Enum.join("\n\n")
      web_page = %WebPage{markdown: markdown}
      
      expect(Text, :split, fn ^markdown -> 
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
      
      expect(Text, :summarize, fn ^markdown -> 
        {:error, "API error"}
      end)
      
      assert {:error, "API error", ^web_page} = Mulberry.Document.generate_summary(web_page)
    end

    test "handles empty markdown gracefully" do
      web_page = %WebPage{url: Faker.Internet.url(), markdown: ""}
      
      # Should not crash
      assert {:ok, ""} = Mulberry.Document.to_text(web_page)
      
      expect(Text, :split, fn "" -> [""] end)
      assert {:ok, [""]} = Mulberry.Document.to_chunks(web_page)
    end
  end
end