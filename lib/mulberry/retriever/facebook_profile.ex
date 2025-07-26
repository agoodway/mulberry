defmodule Mulberry.Retriever.FacebookProfile do
  @moduledoc """
  Retriever implementation for fetching Facebook profile data from the ScrapeCreators API.

  This retriever fetches comprehensive Facebook profile information including business details,
  engagement metrics, and advertising status.

  ## Configuration

  Requires the `SCRAPECREATORS_API_KEY` environment variable or `:scrapecreators_api_key` in config.

  ## Examples

      # Fetch a Facebook profile
      {:ok, response} = Mulberry.Retriever.FacebookProfile.get("https://www.facebook.com/copperkettleyqr")
      
      # The response contains the profile data
      profile_data = response.content
      profile = Mulberry.Document.FacebookProfile.new(profile_data)
      
      # Using with Mulberry.Retriever
      {:ok, response} = Mulberry.Retriever.get(
        Mulberry.Retriever.FacebookProfile,
        "https://www.facebook.com/nike"
      )
  """

  require Logger
  @behaviour Mulberry.Retriever

  @facebook_profile_url "https://api.scrapecreators.com/v1/facebook/profile"

  @impl true
  @spec get(String.t(), Keyword.t()) :: {:ok, Mulberry.Retriever.Response.t()} | {:error, any()}
  def get(url, opts \\ []) do
    api_key = Mulberry.config(:scrapecreators_api_key)

    if api_key do
      fetch_profile(url, api_key, opts)
    else
      Logger.error("#{__MODULE__}.get/2 missing SCRAPECREATORS_API_KEY")
      return_error(:missing_api_key, opts)
    end
  end

  defp fetch_profile(facebook_url, api_key, opts) do
    params = %{url: facebook_url}
    headers = %{"x-api-key" => api_key}

    responder = Keyword.get(opts, :responder, &Mulberry.Retriever.Response.default_responder/1)

    case Req.get(@facebook_profile_url, headers: headers, params: params) do
      {:ok, %Req.Response{status: status, body: body}} when status < 400 ->
        handle_success_response(body, responder)

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("#{__MODULE__}.get/2 API error status=#{status} body=#{inspect(body)}")

        %Mulberry.Retriever.Response{status: :failed, content: nil}
        |> responder.()

      {:error, error} ->
        Logger.error("#{__MODULE__}.get/2 request error=#{inspect(error)}")

        %Mulberry.Retriever.Response{status: :failed, content: nil}
        |> responder.()
    end
  end

  defp handle_success_response(body, responder) when is_map(body) do
    # Check if the response contains an error
    case body do
      %{"error" => error} ->
        Logger.error("#{__MODULE__}.get/2 API returned error: #{inspect(error)}")

        %Mulberry.Retriever.Response{status: :failed, content: nil}
        |> responder.()

      profile_data ->
        # Transform the API response to match our document structure
        transformed_data = transform_profile_data(profile_data)

        %Mulberry.Retriever.Response{status: :ok, content: transformed_data}
        |> responder.()
    end
  end

  defp handle_success_response(body, responder) do
    Logger.error("#{__MODULE__}.get/2 unexpected response format: #{inspect(body)}")

    %Mulberry.Retriever.Response{status: :failed, content: nil}
    |> responder.()
  end

  defp return_error(_reason, opts) do
    responder = Keyword.get(opts, :responder, &Mulberry.Retriever.Response.default_responder/1)

    %Mulberry.Retriever.Response{status: :failed, content: nil}
    |> responder.()
  end

  defp transform_profile_data(data) do
    %{
      id: data["id"],
      name: data["name"],
      url: data["url"],
      gender: data["gender"],
      cover_photo: data["coverPhoto"],
      profile_photo: data["profilePhoto"],
      is_business_page_active: data["isBusinessPageActive"] || false,
      page_intro: data["pageIntro"],
      category: data["category"],
      address: data["address"],
      email: data["email"],
      links: data["links"] || [],
      phone: data["phone"],
      website: data["website"],
      services: data["services"],
      price_range: data["priceRange"],
      rating: data["rating"],
      rating_count: data["ratingCount"],
      like_count: data["likeCount"],
      follower_count: data["followerCount"],
      ad_library: data["adLibrary"],
      creation_date: data["creationDate"]
    }
  end
end
