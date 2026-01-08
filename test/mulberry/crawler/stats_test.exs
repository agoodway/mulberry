defmodule Mulberry.Crawler.StatsTest do
  use ExUnit.Case, async: true

  alias Mulberry.Crawler.Stats

  describe "new/0" do
    test "creates stats with all counters at zero" do
      stats = Stats.new()

      assert stats.urls_crawled == 0
      assert stats.urls_failed == 0
      assert stats.urls_discovered == 0
      assert stats.urls_filtered == 0
      assert stats.urls_robots_blocked == 0
      assert stats.status_codes == %{}
      assert stats.errors_by_category == %{}
      assert stats.per_domain == %{}
      assert stats.start_time == nil
      assert stats.end_time == nil
    end
  end

  describe "start/1" do
    test "records start time" do
      stats = Stats.new() |> Stats.start()

      assert is_integer(stats.start_time)
      # monotonic_time can be negative, just check it's set
      assert stats.start_time != nil
    end
  end

  describe "record_success/4" do
    test "increments urls_crawled" do
      stats =
        Stats.new()
        |> Stats.record_success("example.com", 200, 100)

      assert stats.urls_crawled == 1
    end

    test "tracks status code" do
      stats =
        Stats.new()
        |> Stats.record_success("example.com", 200, 100)
        |> Stats.record_success("example.com", 200, 100)
        |> Stats.record_success("example.com", 301, 100)

      assert stats.status_codes[200] == 2
      assert stats.status_codes[301] == 1
    end

    test "tracks per-domain stats" do
      stats =
        Stats.new()
        |> Stats.record_success("example.com", 200, 100)
        |> Stats.record_success("example.com", 200, 200)
        |> Stats.record_success("other.com", 200, 50)

      assert stats.per_domain["example.com"].urls_crawled == 2
      assert stats.per_domain["example.com"].avg_response_time_ms == 150.0
      assert stats.per_domain["other.com"].urls_crawled == 1
      assert stats.per_domain["other.com"].avg_response_time_ms == 50.0
    end
  end

  describe "record_failure/4" do
    test "increments urls_failed" do
      stats =
        Stats.new()
        |> Stats.record_failure("example.com", :timeout, "Connection timed out")

      assert stats.urls_failed == 1
    end

    test "tracks error category" do
      stats =
        Stats.new()
        |> Stats.record_failure("example.com", :timeout, "timeout")
        |> Stats.record_failure("example.com", :timeout, "timeout")
        |> Stats.record_failure("example.com", :dns, "nxdomain")

      assert stats.errors_by_category[:timeout] == 2
      assert stats.errors_by_category[:dns] == 1
    end

    test "tracks per-domain failures" do
      stats =
        Stats.new()
        |> Stats.record_failure("example.com", :timeout, "timeout")
        |> Stats.record_failure("example.com", :dns, "dns error")

      assert stats.per_domain["example.com"].urls_failed == 2
    end
  end

  describe "record_discovered/2" do
    test "adds to discovered count" do
      stats =
        Stats.new()
        |> Stats.record_discovered(10)
        |> Stats.record_discovered(5)

      assert stats.urls_discovered == 15
    end
  end

  describe "record_filtered/2" do
    test "adds to filtered count" do
      stats =
        Stats.new()
        |> Stats.record_filtered(3)
        |> Stats.record_filtered(7)

      assert stats.urls_filtered == 10
    end
  end

  describe "record_robots_blocked/2" do
    test "adds to robots blocked count" do
      stats =
        Stats.new()
        |> Stats.record_robots_blocked(2)
        |> Stats.record_robots_blocked(3)

      assert stats.urls_robots_blocked == 5
    end
  end

  describe "finalize/1" do
    test "records end time" do
      stats = Stats.new() |> Stats.finalize()

      assert is_integer(stats.end_time)
      # monotonic_time can be negative, just check it's set
      assert stats.end_time != nil
    end
  end

  describe "duration_ms/1" do
    test "returns nil when not started" do
      stats = Stats.new()

      assert Stats.duration_ms(stats) == nil
    end

    test "returns nil when not finalized" do
      stats = Stats.new() |> Stats.start()

      assert Stats.duration_ms(stats) == nil
    end

    test "returns duration when started and finalized" do
      stats =
        Stats.new()
        |> Stats.start()
        |> Stats.finalize()

      duration = Stats.duration_ms(stats)

      assert is_integer(duration)
      assert duration >= 0
    end
  end

  describe "categorize_error/1" do
    test "categorizes timeout errors" do
      assert Stats.categorize_error(%{reason: :timeout}) == :timeout
      assert Stats.categorize_error(%{reason: :connect_timeout}) == :timeout
      assert Stats.categorize_error(:timeout) == :timeout
    end

    test "categorizes DNS errors" do
      assert Stats.categorize_error(%{reason: :nxdomain}) == :dns
      assert Stats.categorize_error(:nxdomain) == :dns
    end

    test "categorizes connection errors" do
      assert Stats.categorize_error(%{reason: :econnrefused}) == :connection
      assert Stats.categorize_error(%{reason: :econnreset}) == :connection
      assert Stats.categorize_error(%{reason: :closed}) == :connection
      assert Stats.categorize_error(:econnrefused) == :connection
    end

    test "categorizes parse errors" do
      assert Stats.categorize_error({:parse, "invalid JSON"}) == :parse
      assert Stats.categorize_error(:parse_error) == :parse
    end

    test "categorizes rate limited errors" do
      assert Stats.categorize_error(:rate_limited) == :rate_limited
      assert Stats.categorize_error({:rate_limited, "too many requests"}) == :rate_limited
    end

    test "categorizes HTTP errors" do
      assert Stats.categorize_error({:http_error, 404}) == :http_error
      assert Stats.categorize_error({:status, 500}) == :http_error
    end

    test "returns unknown for unrecognized errors" do
      assert Stats.categorize_error("some random error") == :unknown
      assert Stats.categorize_error({:weird, :error}) == :unknown
    end
  end

  describe "format_summary/1" do
    test "formats a complete summary" do
      stats =
        Stats.new()
        |> Stats.start()
        |> Stats.record_success("example.com", 200, 100)
        |> Stats.record_success("example.com", 200, 150)
        |> Stats.record_failure("example.com", :timeout, "timeout")
        |> Stats.record_discovered(10)
        |> Stats.record_filtered(2)
        |> Stats.record_robots_blocked(1)
        |> Stats.finalize()

      summary = Stats.format_summary(stats)

      assert String.contains?(summary, "CRAWL SUMMARY")
      assert String.contains?(summary, "Crawled:")
      assert String.contains?(summary, "Failed:")
      assert String.contains?(summary, "Discovered:")
      assert String.contains?(summary, "HTTP Status Codes:")
      assert String.contains?(summary, "200:")
      assert String.contains?(summary, "timeout:")
    end

    test "handles empty stats" do
      stats = Stats.new()
      summary = Stats.format_summary(stats)

      assert String.contains?(summary, "CRAWL SUMMARY")
      assert String.contains?(summary, "Crawled:")
    end
  end

  describe "to_map/1" do
    test "includes duration_ms" do
      stats =
        Stats.new()
        |> Stats.start()
        |> Stats.record_success("example.com", 200, 100)
        |> Stats.finalize()

      map = Stats.to_map(stats)

      assert Map.has_key?(map, :duration_ms)
      assert is_integer(map.duration_ms)
    end
  end

  describe "combined workflow" do
    test "tracks complete crawl session" do
      stats =
        Stats.new()
        |> Stats.start()
        |> Stats.record_discovered(100)
        |> Stats.record_success("site1.com", 200, 100)
        |> Stats.record_success("site1.com", 200, 120)
        |> Stats.record_success("site2.com", 301, 80)
        |> Stats.record_failure("site3.com", :timeout, "Connection timed out")
        |> Stats.record_failure("site4.com", :dns, "NXDOMAIN")
        |> Stats.record_filtered(10)
        |> Stats.record_robots_blocked(5)
        |> Stats.finalize()

      assert stats.urls_crawled == 3
      assert stats.urls_failed == 2
      assert stats.urls_discovered == 100
      assert stats.urls_filtered == 10
      assert stats.urls_robots_blocked == 5

      assert stats.status_codes[200] == 2
      assert stats.status_codes[301] == 1

      assert stats.errors_by_category[:timeout] == 1
      assert stats.errors_by_category[:dns] == 1

      assert stats.per_domain["site1.com"].urls_crawled == 2
      assert stats.per_domain["site1.com"].avg_response_time_ms == 110.0
      assert stats.per_domain["site2.com"].urls_crawled == 1
      assert stats.per_domain["site3.com"].urls_failed == 1
      assert stats.per_domain["site4.com"].urls_failed == 1

      assert Stats.duration_ms(stats) != nil
    end
  end
end
