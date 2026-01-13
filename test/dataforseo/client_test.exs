defmodule DataForSEO.ClientTest do
  use ExUnit.Case, async: false
  use Mimic

  alias DataForSEO.Client

  setup :set_mimic_global

  setup do
    # Set up test credentials
    Application.put_env(:mulberry, :dataforseo,
      username: "test_user",
      password: "test_pass"
    )

    on_exit(fn ->
      Application.delete_env(:mulberry, :dataforseo)
    end)

    :ok
  end

  describe "create_task/2" do
    test "creates task successfully with valid credentials" do
      task_type = "serp/google/events"
      payload = [%{"keyword" => "concerts", "location" => "New York"}]
      expected_url = "https://api.dataforseo.com/v3/#{task_type}/task_post"

      expect(Req, :post, fn url, opts ->
        assert url == expected_url
        assert opts[:auth] == {:basic, "test_user:test_pass"}
        assert opts[:json] == payload

        assert opts[:headers] == [
                 {"content-type", "application/json"},
                 {"accept", "application/json"}
               ]

        assert opts[:retry] == false

        {:ok, %{status: 200, body: %{"status_code" => 20_000, "tasks" => [%{"id" => "task123"}]}}}
      end)

      assert {:ok, response} = Client.create_task(task_type, payload)
      assert response["status_code"] == 20_000
    end

    test "returns error when credentials are missing" do
      Application.delete_env(:mulberry, :dataforseo)

      assert {:error, :missing_credentials} = Client.create_task("serp/google/events", [])
    end

    test "returns error when credentials are nil" do
      Application.put_env(:mulberry, :dataforseo, username: nil, password: nil)

      assert {:error, :missing_credentials} = Client.create_task("serp/google/events", [])
    end

    test "handles API error status codes" do
      expect(Req, :post, fn _url, _opts ->
        {:ok,
         %{status: 200, body: %{"status_code" => 40_100, "status_message" => "Invalid API key"}}}
      end)

      assert {:error, {:api_error, 40_100, "Invalid API key"}} =
               Client.create_task("serp/google/events", [])
    end

    test "handles HTTP 400 error" do
      expect(Req, :post, fn _url, _opts ->
        {:ok, %{status: 400, body: %{"error" => "Bad Request"}}}
      end)

      assert {:error, {:api_error, 400, %{"error" => "Bad Request"}}} =
               Client.create_task("serp/google/events", [])
    end

    test "retries on 429 rate limit and succeeds" do
      expect(Req, :post, 2, fn _url, _opts ->
        case Process.get(:attempt_count, 0) do
          0 ->
            Process.put(:attempt_count, 1)
            {:ok, %{status: 429, body: %{"error" => "Rate limited"}}}

          1 ->
            {:ok, %{status: 200, body: %{"status_code" => 20_000}}}
        end
      end)

      assert {:ok, response} = Client.create_task("serp/google/events", [])
      assert response["status_code"] == 20_000
    end

    test "retries on 503 service unavailable" do
      expect(Req, :post, 2, fn _url, _opts ->
        case Process.get(:attempt_count, 0) do
          0 ->
            Process.put(:attempt_count, 1)
            {:ok, %{status: 503, body: %{"error" => "Service unavailable"}}}

          1 ->
            {:ok, %{status: 200, body: %{"status_code" => 20_000}}}
        end
      end)

      assert {:ok, response} = Client.create_task("serp/google/events", [])
      assert response["status_code"] == 20_000
    end

    test "fails after max retries" do
      expect(Req, :post, 4, fn _url, _opts ->
        {:ok, %{status: 503, body: %{"error" => "Service unavailable"}}}
      end)

      assert {:error, {:api_error, 503, %{"error" => "Service unavailable"}}} =
               Client.create_task("serp/google/events", [])
    end

    test "handles network errors" do
      expect(Req, :post, fn _url, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      assert {:error, {:request_failed, %Req.TransportError{reason: :timeout}}} =
               Client.create_task("serp/google/events", [])
    end
  end

  describe "create_live_task/2" do
    test "creates live task successfully with valid credentials" do
      task_type = "business_data/business_listings/search"

      payload = [
        %{"categories" => ["pizza_restaurant"], "location_coordinate" => "40.7128,-74.0060,5"}
      ]

      expected_url = "https://api.dataforseo.com/v3/#{task_type}/live"

      expect(Req, :post, fn url, opts ->
        assert url == expected_url
        assert opts[:auth] == {:basic, "test_user:test_pass"}
        assert opts[:json] == payload

        assert opts[:headers] == [
                 {"content-type", "application/json"},
                 {"accept", "application/json"}
               ]

        assert opts[:retry] == false

        {:ok,
         %{
           status: 200,
           body: %{
             "status_code" => 20_000,
             "tasks" => [
               %{
                 "result" => [
                   %{
                     "total_count" => 2,
                     "items" => [
                       %{"title" => "Joe's Pizza", "category" => "Pizza restaurant"}
                     ]
                   }
                 ]
               }
             ]
           }
         }}
      end)

      assert {:ok, response} = Client.create_live_task(task_type, payload)
      assert response["status_code"] == 20_000
      assert response["tasks"] != nil
    end

    test "returns error when credentials are missing" do
      Application.delete_env(:mulberry, :dataforseo)

      assert {:error, :missing_credentials} =
               Client.create_live_task("business_data/business_listings/search", [])
    end

    test "handles API error responses" do
      expect(Req, :post, fn _url, _opts ->
        {:ok,
         %{
           status: 200,
           body: %{"status_code" => 40_100, "status_message" => "Invalid parameters"}
         }}
      end)

      assert {:error, {:api_error, 40_100, "Invalid parameters"}} =
               Client.create_live_task("business_data/business_listings/search", [])
    end

    test "retries on 500 server error and succeeds" do
      expect(Req, :post, 2, fn _url, _opts ->
        case Process.get(:attempt_count, 0) do
          0 ->
            Process.put(:attempt_count, 1)
            {:ok, %{status: 500, body: %{"error" => "Server Error"}}}

          1 ->
            {:ok, %{status: 200, body: %{"status_code" => 20_000, "tasks" => []}}}
        end
      end)

      assert {:ok, _response} =
               Client.create_live_task("business_data/business_listings/search", [])
    end

    test "handles request timeout" do
      expect(Req, :post, fn _url, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      assert {:error, {:request_failed, %Req.TransportError{reason: :timeout}}} =
               Client.create_live_task("business_data/business_listings/search", [])
    end
  end

  describe "check_ready_tasks/1" do
    test "checks for ready tasks successfully" do
      task_type = "serp/google/events"
      expected_url = "https://api.dataforseo.com/v3/#{task_type}/tasks_ready"

      expect(Req, :get, fn url, opts ->
        assert url == expected_url
        assert opts[:auth] == {:basic, "test_user:test_pass"}

        {:ok,
         %{
           status: 200,
           body: %{
             "status_code" => 20_000,
             "tasks" => [
               %{"id" => "task123", "result_count" => 1}
             ]
           }
         }}
      end)

      assert {:ok, response} = Client.check_ready_tasks(task_type)
      assert response["status_code"] == 20_000
    end

    test "returns error when credentials are missing" do
      Application.delete_env(:mulberry, :dataforseo)

      assert {:error, :missing_credentials} = Client.check_ready_tasks("serp/google/events")
    end

    test "retries on 500 server error" do
      expect(Req, :get, 2, fn _url, _opts ->
        case Process.get(:attempt_count, 0) do
          0 ->
            Process.put(:attempt_count, 1)
            {:ok, %{status: 500, body: %{"error" => "Internal Server Error"}}}

          1 ->
            {:ok, %{status: 200, body: %{"status_code" => 20_000, "tasks" => []}}}
        end
      end)

      assert {:ok, response} = Client.check_ready_tasks("serp/google/events")
      assert response["status_code"] == 20_000
    end
  end

  describe "fetch_task_results/3" do
    test "fetches task results successfully with default endpoint" do
      task_type = "serp/google/events"
      task_id = "task123"
      expected_url = "https://api.dataforseo.com/v3/#{task_type}/task_get/advanced/#{task_id}"

      expect(Req, :get, fn url, opts ->
        assert url == expected_url
        assert opts[:auth] == {:basic, "test_user:test_pass"}

        {:ok,
         %{
           status: 200,
           body: %{
             "status_code" => 20_000,
             "tasks" => [
               %{
                 "id" => task_id,
                 "result" => [%{"items" => []}]
               }
             ]
           }
         }}
      end)

      assert {:ok, response} = Client.fetch_task_results(task_type, task_id)
      assert response["status_code"] == 20_000
    end

    test "fetches task results with custom endpoint" do
      task_type = "serp/google/events"
      task_id = "task123"
      endpoint = "regular"
      expected_url = "https://api.dataforseo.com/v3/#{task_type}/task_get/#{endpoint}/#{task_id}"

      expect(Req, :get, fn url, _opts ->
        assert url == expected_url
        {:ok, %{status: 200, body: %{"status_code" => 20_000}}}
      end)

      assert {:ok, _response} = Client.fetch_task_results(task_type, task_id, endpoint)
    end

    test "handles invalid response body" do
      expect(Req, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: "invalid json string"}}
      end)

      assert {:error, {:invalid_response, "invalid json string"}} =
               Client.fetch_task_results("serp/google/events", "task123")
    end

    test "retries on 502 bad gateway" do
      expect(Req, :get, 2, fn _url, _opts ->
        case Process.get(:attempt_count, 0) do
          0 ->
            Process.put(:attempt_count, 1)
            {:ok, %{status: 502, body: %{"error" => "Bad Gateway"}}}

          1 ->
            {:ok, %{status: 200, body: %{"status_code" => 20_000}}}
        end
      end)

      assert {:ok, response} = Client.fetch_task_results("serp/google/events", "task123")
      assert response["status_code"] == 20_000
    end
  end
end
