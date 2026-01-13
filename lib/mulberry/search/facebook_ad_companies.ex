defmodule Mulberry.Search.FacebookAdCompanies do
  @behaviour Mulberry.Search.Behaviour
  @moduledoc """
  Facebook Ad Companies search using ScrapeCreators API

  Searches for companies by name and retrieves their Facebook ad library page information.

  ## Configuration

  Requires the `SCRAPECREATORS_API_KEY` environment variable or `:scrapecreators_api_key` in config.

  ## Examples

      # Search for companies by name
      {:ok, companies} = Mulberry.search(Mulberry.Search.FacebookAdCompanies, "Nike")
      
      # Access company information
      company = List.first(companies)
      company.page_id                # => "15087023444"
      company.name                   # => "Nike"
      company.category               # => "Sportswear Store"
      company.likes                  # => 39558683
      company.verification           # => "BLUE_VERIFIED"
      company.ig_username            # => "nike"
      company.ig_followers           # => 302060936
      
      # Get raw response for pagination
      {:ok, response} = Mulberry.Search.FacebookAdCompanies.search("Nike", 10)
      {:ok, companies} = Mulberry.Search.FacebookAdCompanies.to_documents(response)

  ## API Reference

  https://api.scrapecreators.com/v1/facebook/adLibrary/search/companies
  """

  require Logger

  @facebook_companies_url "https://api.scrapecreators.com/v1/facebook/adLibrary/search/companies"

  @impl true
  @spec search(binary(), pos_integer(), keyword()) :: {:ok, map()} | {:error, binary()}
  def search(query, _count \\ 20, opts \\ []) do
    retriever = Keyword.get(opts, :retriever, Mulberry.Retriever.Req)

    request_opts = [
      params: %{query: query},
      headers: [
        {"x-api-key", Mulberry.config(:scrapecreators_api_key)}
      ]
    ]

    case Mulberry.Retriever.get(retriever, @facebook_companies_url, request_opts) do
      {:ok, response} -> {:ok, response.content}
      {:error, _} = error -> error
    end
  end

  @impl true
  @spec to_documents(any()) :: {:ok, [Mulberry.Document.FacebookAdCompany.t()]} | {:error, atom()}
  def to_documents(results) do
    case results do
      %{"searchResults" => companies} when is_list(companies) ->
        docs = Enum.map(companies, &company_to_document/1)
        {:ok, docs}

      %{"searchResults" => []} ->
        {:ok, []}

      %{"error" => error} ->
        Logger.error(
          "#{__MODULE__}.to_documents/1 Facebook companies search failed: #{inspect(error)}"
        )

        {:error, :search_failed}

      response ->
        Logger.error(
          "#{__MODULE__}.to_documents/1 unexpected response format: #{inspect(response)}"
        )

        {:error, :parse_search_results_failed}
    end
  end

  defp company_to_document(company) do
    attrs = %{
      page_id: company["page_id"],
      name: company["name"],
      category: company["category"],
      image_uri: company["image_uri"],
      likes: company["likes"],
      verification: company["verification"],
      country: company["country"],
      entity_type: company["entity_type"],
      ig_username: company["ig_username"],
      ig_followers: company["ig_followers"],
      ig_verification: company["ig_verification"],
      page_alias: company["page_alias"],
      page_is_deleted: company["page_is_deleted"]
    }

    Mulberry.Document.FacebookAdCompany.new(attrs)
  end
end
