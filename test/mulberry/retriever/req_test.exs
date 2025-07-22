defmodule Mulberry.Retriever.ReqTest do
  use ExUnit.Case, async: true
  use Mimic
  doctest Mulberry.Retriever.Req

  alias Mulberry.Retriever.Req, as: ReqRetriever
  alias Mulberry.Retriever.Response

  describe "get/2" do
    test "successfully retrieves content" do
      url = Faker.Internet.url()
      body = Faker.Lorem.paragraph()
      
      expect(Req, :get, fn ^url, opts -> 
        assert opts[:headers] == %{}
        assert opts[:params] == %{}
        {:ok, %Req.Response{status: 200, body: body, headers: []}}
      end)
      
      assert {:ok, response} = ReqRetriever.get(url)
      assert response.status == :ok
      assert response.content == body
    end

    test "handles redirect response" do
      url = Faker.Internet.url()
      redirect_url = Faker.Internet.url()
      
      expect(Req, :get, fn ^url, _ -> 
        {:ok, %Req.Response{
          status: 301, 
          body: "",
          headers: [{"location", redirect_url}]
        }}
      end)
      
      assert {:ok, response} = ReqRetriever.get(url)
      assert response.status == :ok
      assert response.content == ""
    end

    test "handles request error" do
      url = Faker.Internet.url()
      
      expect(Req, :get, fn ^url, _ -> 
        {:error, %Mint.TransportError{reason: :timeout}}
      end)
      
      assert {:error, response} = ReqRetriever.get(url)
      assert response.status == :failed
      assert response.content == nil
    end

    test "passes custom options" do
      url = Faker.Internet.url()
      custom_opts = [params: %{key: "value"}, headers: %{"User-Agent" => "Test"}]
      
      expect(Req, :get, fn ^url, opts -> 
        assert opts[:params] == %{key: "value"}
        assert opts[:headers] == %{"User-Agent" => "Test"}
        {:ok, %Req.Response{status: 200, body: "OK", headers: []}}
      end)
      
      assert {:ok, response} = ReqRetriever.get(url, custom_opts)
      assert response.status == :ok
      assert response.content == "OK"
    end

    test "applies custom responder function" do
      url = Faker.Internet.url()
      custom_responder = fn response ->
        {:ok, Map.put(response, :custom, true)}
      end
      
      expect(Req, :get, fn ^url, _ -> 
        {:ok, %Req.Response{status: 200, body: "Test", headers: []}}
      end)
      
      assert {:ok, response} = ReqRetriever.get(url, responder: custom_responder)
      assert response.custom == true
    end

    test "handles non-200 status with default responder" do
      url = Faker.Internet.url()
      
      expect(Req, :get, fn ^url, _ -> 
        {:ok, %Req.Response{status: 404, body: "Not Found", headers: []}}
      end)
      
      assert {:error, response} = ReqRetriever.get(url)
      assert response.status == 404
      assert response.body == "Not Found"
    end
  end
end