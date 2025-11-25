defmodule DataForSEO.Schemas.GoogleEventsResultTest do
  use ExUnit.Case, async: true

  alias DataForSEO.Schemas.{GoogleEventsResult, GoogleEvent}

  describe "new/1" do
    test "creates a GoogleEventsResult with events and metadata" do
      attrs = %{
        events: [
          %{title: "Concert 1", type: "event"},
          %{title: "Concert 2", type: "event"}
        ],
        metadata: %{
          total_count: 2,
          items_count: 2,
          keyword: "concerts nyc"
        }
      }

      result = GoogleEventsResult.new(attrs)

      assert %GoogleEventsResult{} = result
      assert length(result.events) == 2
      assert Enum.all?(result.events, &match?(%GoogleEvent{}, &1))
      assert result.metadata.total_count == 2
      assert result.metadata.keyword == "concerts nyc"
    end

    test "creates result with empty events list" do
      attrs = %{
        events: [],
        metadata: %{total_count: 0}
      }

      result = GoogleEventsResult.new(attrs)

      assert result.events == []
      assert result.metadata.total_count == 0
    end

    test "handles missing events key" do
      attrs = %{metadata: %{total_count: 0}}

      result = GoogleEventsResult.new(attrs)

      assert result.events == []
    end

    test "handles missing metadata key" do
      attrs = %{events: [%{title: "Concert"}]}

      result = GoogleEventsResult.new(attrs)

      assert length(result.events) == 1
      assert result.metadata == %{}
    end
  end

  describe "event_count/1" do
    test "returns count of events" do
      result = GoogleEventsResult.new(%{
        events: [
          %{title: "Concert 1"},
          %{title: "Concert 2"},
          %{title: "Concert 3"}
        ],
        metadata: %{}
      })

      assert GoogleEventsResult.event_count(result) == 3
    end

    test "returns 0 for empty events" do
      result = GoogleEventsResult.new(%{events: [], metadata: %{}})

      assert GoogleEventsResult.event_count(result) == 0
    end
  end

  describe "has_events?/1" do
    test "returns true when events exist" do
      result = GoogleEventsResult.new(%{
        events: [%{title: "Concert"}],
        metadata: %{}
      })

      assert GoogleEventsResult.has_events?(result) == true
    end

    test "returns false when no events" do
      result = GoogleEventsResult.new(%{events: [], metadata: %{}})

      assert GoogleEventsResult.has_events?(result) == false
    end
  end

  describe "events_by_date/2" do
    test "filters events by date" do
      result = GoogleEventsResult.new(%{
        events: [
          %{title: "Concert 1", date: "Aug 15"},
          %{title: "Concert 2", date: "Aug 16"},
          %{title: "Concert 3", date: "Aug 15"}
        ],
        metadata: %{}
      })

      filtered = GoogleEventsResult.events_by_date(result, "Aug 15")

      assert length(filtered) == 2
      assert Enum.all?(filtered, fn event -> event.date == "Aug 15" end)
    end

    test "returns empty list when no matches" do
      result = GoogleEventsResult.new(%{
        events: [%{title: "Concert", date: "Aug 15"}],
        metadata: %{}
      })

      filtered = GoogleEventsResult.events_by_date(result, "Aug 20")

      assert filtered == []
    end
  end

  describe "events_with_tickets/1" do
    test "filters events that have tickets_url" do
      result = GoogleEventsResult.new(%{
        events: [
          %{title: "Concert 1", tickets_url: "https://tickets1.com"},
          %{title: "Concert 2", tickets_url: nil},
          %{title: "Concert 3", tickets_url: "https://tickets3.com"}
        ],
        metadata: %{}
      })

      filtered = GoogleEventsResult.events_with_tickets(result)

      assert length(filtered) == 2
      assert Enum.all?(filtered, fn event -> not is_nil(event.tickets_url) end)
    end

    test "returns empty list when no events have tickets" do
      result = GoogleEventsResult.new(%{
        events: [
          %{title: "Concert 1", tickets_url: nil},
          %{title: "Concert 2"}
        ],
        metadata: %{}
      })

      filtered = GoogleEventsResult.events_with_tickets(result)

      assert filtered == []
    end
  end

  describe "events_by_start_datetime/2" do
    test "filters events by start_datetime" do
      result = GoogleEventsResult.new(%{
        events: [
          %{
            title: "Concert 1",
            event_dates: %{start_datetime: "2024-08-15T19:00:00"}
          },
          %{
            title: "Concert 2",
            event_dates: %{start_datetime: "2024-08-16T20:00:00"}
          },
          %{
            title: "Concert 3",
            event_dates: %{start_datetime: "2024-08-15T19:00:00"}
          }
        ],
        metadata: %{}
      })

      filtered = GoogleEventsResult.events_by_start_datetime(result, "2024-08-15T19:00:00")

      assert length(filtered) == 2
    end

    test "returns empty list when no matches" do
      result = GoogleEventsResult.new(%{
        events: [
          %{event_dates: %{start_datetime: "2024-08-15T19:00:00"}}
        ],
        metadata: %{}
      })

      filtered = GoogleEventsResult.events_by_start_datetime(result, "2024-08-20T19:00:00")

      assert filtered == []
    end

    test "handles events without event_dates" do
      result = GoogleEventsResult.new(%{
        events: [
          %{title: "Concert 1", event_dates: nil},
          %{title: "Concert 2"}
        ],
        metadata: %{}
      })

      filtered = GoogleEventsResult.events_by_start_datetime(result, "2024-08-15T19:00:00")

      assert filtered == []
    end
  end

  describe "events_in_range/3" do
    test "filters events within datetime range" do
      result = GoogleEventsResult.new(%{
        events: [
          %{event_dates: %{start_datetime: "2024-08-15T19:00:00"}},
          %{event_dates: %{start_datetime: "2024-08-16T20:00:00"}},
          %{event_dates: %{start_datetime: "2024-08-17T21:00:00"}},
          %{event_dates: %{start_datetime: "2024-08-20T19:00:00"}}
        ],
        metadata: %{}
      })

      filtered =
        GoogleEventsResult.events_in_range(
          result,
          "2024-08-15T00:00:00",
          "2024-08-17T23:59:59"
        )

      assert length(filtered) == 3
    end

    test "returns empty list when no events in range" do
      result = GoogleEventsResult.new(%{
        events: [
          %{event_dates: %{start_datetime: "2024-08-15T19:00:00"}}
        ],
        metadata: %{}
      })

      filtered =
        GoogleEventsResult.events_in_range(result, "2024-08-20T00:00:00", "2024-08-25T23:59:59")

      assert filtered == []
    end

    test "handles events without event_dates" do
      result = GoogleEventsResult.new(%{
        events: [
          %{title: "Concert", event_dates: nil}
        ],
        metadata: %{}
      })

      filtered =
        GoogleEventsResult.events_in_range(result, "2024-08-15T00:00:00", "2024-08-20T23:59:59")

      assert filtered == []
    end
  end

  describe "ticket_vendors/1" do
    test "returns unique vendor domains" do
      result = GoogleEventsResult.new(%{
        events: [
          %{
            information_and_tickets: [
              %{domain: "www.ticketmaster.com"},
              %{domain: "www.stubhub.com"}
            ]
          },
          %{
            information_and_tickets: [
              %{domain: "www.ticketmaster.com"},
              %{domain: "www.eventbrite.com"}
            ]
          }
        ],
        metadata: %{}
      })

      vendors = GoogleEventsResult.ticket_vendors(result)

      assert length(vendors) == 3
      assert "www.eventbrite.com" in vendors
      assert "www.stubhub.com" in vendors
      assert "www.ticketmaster.com" in vendors
      assert vendors == Enum.sort(vendors)
    end

    test "filters out nil domains" do
      result = GoogleEventsResult.new(%{
        events: [
          %{
            information_and_tickets: [
              %{domain: "www.ticketmaster.com"},
              %{domain: nil}
            ]
          }
        ],
        metadata: %{}
      })

      vendors = GoogleEventsResult.ticket_vendors(result)

      assert vendors == ["www.ticketmaster.com"]
    end

    test "returns empty list when no ticket vendors" do
      result = GoogleEventsResult.new(%{
        events: [%{information_and_tickets: nil}],
        metadata: %{}
      })

      vendors = GoogleEventsResult.ticket_vendors(result)

      assert vendors == []
    end
  end

  describe "events_by_vendor/2" do
    test "filters events by vendor domain" do
      result = GoogleEventsResult.new(%{
        events: [
          %{
            title: "Concert 1",
            information_and_tickets: [
              %{domain: "www.ticketmaster.com"}
            ]
          },
          %{
            title: "Concert 2",
            information_and_tickets: [
              %{domain: "www.stubhub.com"}
            ]
          },
          %{
            title: "Concert 3",
            information_and_tickets: [
              %{domain: "www.ticketmaster.com"}
            ]
          }
        ],
        metadata: %{}
      })

      filtered = GoogleEventsResult.events_by_vendor(result, "www.ticketmaster.com")

      assert length(filtered) == 2
      assert Enum.all?(filtered, fn event ->
               Enum.any?(event.information_and_tickets, &(&1.domain == "www.ticketmaster.com"))
             end)
    end

    test "returns empty list when no matches" do
      result = GoogleEventsResult.new(%{
        events: [
          %{information_and_tickets: [%{domain: "www.ticketmaster.com"}]}
        ],
        metadata: %{}
      })

      filtered = GoogleEventsResult.events_by_vendor(result, "www.stubhub.com")

      assert filtered == []
    end

    test "handles events without ticket information" do
      result = GoogleEventsResult.new(%{
        events: [
          %{title: "Concert 1", information_and_tickets: nil},
          %{title: "Concert 2"}
        ],
        metadata: %{}
      })

      filtered = GoogleEventsResult.events_by_vendor(result, "www.ticketmaster.com")

      assert filtered == []
    end
  end

  describe "ticket_urls_for_event/1" do
    test "extracts ticket URLs from event" do
      event = GoogleEvent.new(%{
        information_and_tickets: [
          %{
            title: "Ticketmaster",
            url: "https://www.ticketmaster.com/event/123",
            domain: "www.ticketmaster.com"
          },
          %{
            title: "StubHub",
            url: "https://www.stubhub.com/event/456",
            domain: "www.stubhub.com"
          }
        ]
      })

      urls = GoogleEventsResult.ticket_urls_for_event(event)

      assert length(urls) == 2
      assert Enum.any?(urls, &(&1.vendor == "Ticketmaster"))
      assert Enum.any?(urls, &(&1.url == "https://www.stubhub.com/event/456"))
    end

    test "uses domain as vendor when title is nil" do
      event = GoogleEvent.new(%{
        information_and_tickets: [
          %{
            title: nil,
            url: "https://www.ticketmaster.com/event/123",
            domain: "www.ticketmaster.com"
          }
        ]
      })

      urls = GoogleEventsResult.ticket_urls_for_event(event)

      assert List.first(urls).vendor == "www.ticketmaster.com"
    end

    test "returns empty list when no ticket information" do
      event = GoogleEvent.new(%{information_and_tickets: nil})

      urls = GoogleEventsResult.ticket_urls_for_event(event)

      assert urls == []
    end
  end
end
