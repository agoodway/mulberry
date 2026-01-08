defmodule Mulberry.Crawler.CLI.ProgressTest do
  use ExUnit.Case, async: true

  alias Mulberry.Crawler.CLI.Progress

  describe "new/1" do
    test "creates progress with default values" do
      progress = Progress.new()

      assert progress.total_urls == nil
      assert progress.urls_crawled == 0
      assert progress.urls_failed == 0
      assert progress.active_workers == 0
      assert progress.queue_size == 0
      assert progress.verbosity == :normal
    end

    test "creates progress with custom total_urls" do
      progress = Progress.new(total_urls: 100)

      assert progress.total_urls == 100
    end

    test "creates progress with custom verbosity" do
      progress = Progress.new(verbosity: :quiet)

      assert progress.verbosity == :quiet
    end
  end

  describe "update/2" do
    test "updates progress with new stats" do
      progress =
        Progress.new()
        |> Progress.update(%{
          urls_crawled: 50,
          urls_failed: 2,
          active_workers: 5,
          queue_size: 48
        })

      assert progress.urls_crawled == 50
      assert progress.urls_failed == 2
      assert progress.active_workers == 5
      assert progress.queue_size == 48
    end

    test "preserves values not in stats" do
      progress =
        Progress.new(total_urls: 100)
        |> Progress.update(%{urls_crawled: 10})

      assert progress.total_urls == 100
      assert progress.urls_crawled == 10
      assert progress.urls_failed == 0
    end
  end

  describe "render/1" do
    test "returns :ok for quiet mode" do
      progress = Progress.new(verbosity: :quiet)

      assert Progress.render(progress) == :ok
    end
  end

  describe "render_url/3" do
    test "returns :ok for quiet mode" do
      progress = Progress.new(verbosity: :quiet)

      assert Progress.render_url(progress, "http://example.com", :ok) == :ok
    end

    test "returns :ok for normal mode" do
      progress = Progress.new(verbosity: :normal)

      assert Progress.render_url(progress, "http://example.com", :ok) == :ok
    end
  end

  describe "format_summary/1" do
    test "formats stats summary" do
      stats = %{
        urls_crawled: 100,
        urls_failed: 5,
        urls_discovered: 150,
        urls_filtered: 20,
        urls_robots_blocked: 10,
        duration_ms: 5000,
        status_codes: %{200 => 95, 404 => 5},
        errors_by_category: %{timeout: 3, connection: 2},
        per_domain: %{
          "example.com" => %{
            urls_crawled: 80,
            urls_failed: 3,
            total_response_time_ms: 8000
          },
          "other.com" => %{
            urls_crawled: 20,
            urls_failed: 2,
            total_response_time_ms: 2000
          }
        }
      }

      summary = Progress.format_summary(stats)

      assert summary =~ "CRAWL SUMMARY"
      assert summary =~ "URLs Crawled:     100"
      assert summary =~ "URLs Failed:      5"
      assert summary =~ "URLs Discovered:  150"
      assert summary =~ "URLs Filtered:    20"
      assert summary =~ "Robots Blocked:   10"
      assert summary =~ "STATUS CODES"
      assert summary =~ "200: 95"
      assert summary =~ "404: 5"
      assert summary =~ "ERRORS"
      assert summary =~ "timeout: 3"
      assert summary =~ "connection: 2"
      assert summary =~ "TOP DOMAINS"
      assert summary =~ "example.com"
    end

    test "handles empty stats" do
      stats = %{
        urls_crawled: 0,
        urls_failed: 0,
        urls_discovered: 0,
        urls_filtered: 0,
        urls_robots_blocked: 0,
        duration_ms: nil,
        status_codes: %{},
        errors_by_category: %{},
        per_domain: %{}
      }

      summary = Progress.format_summary(stats)

      assert summary =~ "CRAWL SUMMARY"
      assert summary =~ "URLs Crawled:     0"
      assert summary =~ "(none recorded)"
      assert summary =~ "(none)"
    end
  end

  describe "format_brief_summary/1" do
    test "formats brief summary" do
      stats = %{
        urls_crawled: 100,
        urls_failed: 5,
        duration_ms: 5000
      }

      summary = Progress.format_brief_summary(stats)

      assert summary =~ "Crawled 100 URLs"
      assert summary =~ "5 failed"
      assert summary =~ "% success"
      assert summary =~ "5.0s"
    end

    test "handles zero crawled URLs" do
      stats = %{
        urls_crawled: 0,
        urls_failed: 0,
        duration_ms: 100
      }

      summary = Progress.format_brief_summary(stats)

      assert summary =~ "Crawled 0 URLs"
      assert summary =~ "0.0% success"
    end
  end
end
