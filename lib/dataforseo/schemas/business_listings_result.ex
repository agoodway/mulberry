defmodule DataForSEO.Schemas.BusinessListingsResult do
  @moduledoc """
  Schema for business listings search results from DataForSEO Business Listings API.

  Contains a collection of business listings along with metadata about the total
  number of results available.

  ## Fields

  - `:total_count` - Total number of business listings matching the search criteria
  - `:items` - List of `DataForSEO.Schemas.BusinessListing` structs

  ## Examples

      iex> result = %DataForSEO.Schemas.BusinessListingsResult{
      ...>   total_count: 36,
      ...>   items: [%DataForSEO.Schemas.BusinessListing{title: "Joe's Pizza"}]
      ...> }
      %DataForSEO.Schemas.BusinessListingsResult{total_count: 36, items: [%DataForSEO.Schemas.BusinessListing{...}]}

  """

  alias DataForSEO.Schemas.BusinessListing

  @type t :: %__MODULE__{
          total_count: integer() | nil,
          items: [BusinessListing.t()]
        }

  defstruct [
    :total_count,
    items: []
  ]

  @doc """
  Creates a BusinessListingsResult struct from a map of attributes.

  Parses the result data from the DataForSEO API response and converts
  each item into a `BusinessListing` struct.

  ## Parameters

  - `attrs` - Map containing "total_count" and "items" from the API response

  ## Returns

  A `BusinessListingsResult` struct with parsed business listings.

  ## Examples

      iex> DataForSEO.Schemas.BusinessListingsResult.new(%{
      ...>   "total_count" => 36,
      ...>   "items" => [
      ...>     %{"title" => "Joe's Pizza", "category" => "Pizza restaurant"}
      ...>   ]
      ...> })
      %DataForSEO.Schemas.BusinessListingsResult{
        total_count: 36,
        items: [%DataForSEO.Schemas.BusinessListing{title: "Joe's Pizza", ...}]
      }

  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    items =
      attrs
      |> Map.get("items", [])
      |> Enum.map(&BusinessListing.new/1)
      |> Enum.map(&BusinessListing.with_id/1)

    %__MODULE__{
      total_count: attrs["total_count"],
      items: items
    }
  end
end
