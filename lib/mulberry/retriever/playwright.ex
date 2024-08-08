defmodule Mulberry.Retriever.Playwright do
  @behaviour Mulberry.Retriever
  require Logger

  @impl true
  def get(url, opts \\ []) do
    responder =
      Keyword.get(opts, :responder, &Mulberry.Retriever.Response.default_responder/1)

    case Playwright.launch(:chromium) do
      {:ok, browser} ->
        page =
          Playwright.Browser.new_page(browser)

        Playwright.Page.goto(page, url)
        Playwright.Page.wait_for_load_state(page, "domcontentloaded")

        html =
          page
          |> Playwright.Page.locator("html")
          |> Playwright.Locator.inner_html()

        Playwright.Browser.close(browser)

        responder.(%Mulberry.Retriever.Response{status: :ok, content: html})
    end
  end
end
