defmodule Mix.Tasks.FetchUrlTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
  import Mimic

  alias Mix.Tasks.FetchUrl
  alias Mulberry.Retriever.Playwright
  alias Mulberry.Retriever.Response

  setup :verify_on_exit!

  describe "title generation" do
    test "generates title when --title flag is provided" do
      html_content = """
      <html>
        <head><title>Test Page</title></head>
        <body>
          <h1>Understanding Elixir Processes</h1>
          <p>This article explains how Elixir processes work and why they are important for building concurrent applications.</p>
        </body>
      </html>
      """

      expect(Playwright, :get, fn _url, _opts ->
        %Response{
          status: :ok,
          content: html_content
        }
      end)

      expect(Mulberry.Text, :title, fn text, opts ->
        assert text =~ "Understanding Elixir Processes"
        assert opts[:max_words] == 14
        assert opts[:verbose] == false
        {:ok, "Guide to Elixir Process Concurrency"}
      end)

      output = capture_io(fn ->
        FetchUrl.run(["https://example.com", "--title"])
      end)

      assert output =~ "Generating AI title..."
      assert output =~ "AI Generated Title: Guide to Elixir Process Concurrency"
      assert output =~ "================================================================================\n"
    end

    test "shows error when title generation fails" do
      html_content = """
      <html>
        <head><title>Test Page</title></head>
        <body>
          <p>Some content</p>
        </body>
      </html>
      """

      expect(Playwright, :get, fn _url, _opts ->
        %Response{
          status: :ok,
          content: html_content
        }
      end)

      # Mock the Text.title function to simulate failure
      expect(Mulberry.Text, :title, fn _text, _opts ->
        {:error, "API error"}
      end)

      output = capture_io(fn ->
        stderr = capture_io(:stderr, fn ->
          FetchUrl.run(["https://example.com", "--title"])
        end)
        IO.write(stderr)
      end)

      assert output =~ "Generating AI title..."
      assert output =~ "Failed to generate title:"
    end

    test "generates title with text display" do
      html_content = """
      <html>
        <body>
          <h1>Elixir Guide</h1>
          <p>Learn Elixir programming</p>
        </body>
      </html>
      """

      expect(Playwright, :get, fn _url, _opts ->
        %Response{
          status: :ok,
          content: html_content
        }
      end)

      expect(Mulberry.Text, :title, fn _text, _opts ->
        {:ok, "Elixir Programming Guide"}
      end)

      output = capture_io(fn ->
        FetchUrl.run(["https://example.com", "--title", "--show-text"])
      end)

      assert output =~ "Generating AI title..."
      assert output =~ "AI Generated Title: Elixir Programming Guide"
      assert output =~ "Extracted text content:"
      assert output =~ "Elixir Guide"
      assert output =~ "Learn Elixir programming"
    end
  end

  describe "basic functionality" do
    test "requires URL argument" do
      assert_raise Mix.Error, ~r/URL is required/, fn ->
        FetchUrl.run([])
      end
    end

    test "fetches URL successfully" do
      html_content = "<html><body><p>Hello World</p></body></html>"

      expect(Playwright, :get, fn url, _opts ->
        assert url == "https://example.com"
        %Response{
          status: :ok,
          content: html_content
        }
      end)

      output = capture_io(fn ->
        FetchUrl.run(["https://example.com"])
      end)

      assert output =~ "Fetching URL: https://example.com"
      assert output =~ "HTML content preview:"
      assert output =~ "<html><body><p>Hello World</p></body></html>"
    end

    test "shows error on failed fetch" do
      expect(Playwright, :get, fn _url, _opts ->
        %Response{
          status: :failed,
          content: nil
        }
      end)

      output = capture_io(:stderr, fn ->
        assert catch_exit(FetchUrl.run(["https://example.com"])) == {:shutdown, 1}
      end)

      assert output =~ "Failed to fetch URL"
    end
  end
end