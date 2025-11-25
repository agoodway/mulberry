defmodule DataForSEO.Schemas.GoogleEventTest do
  use ExUnit.Case, async: true

  alias DataForSEO.Schemas.GoogleEvent

  describe "new/1" do
    test "creates a GoogleEvent struct from a map" do
      attrs = %{
        type: "event",
        title: "Summer Concert",
        description: "A great concert",
        url: "https://example.com/concert",
        date: "Aug 15",
        position: 1,
        xpath: "/html/body/div"
      }

      event = GoogleEvent.new(attrs)

      assert %GoogleEvent{} = event
      assert event.type == "event"
      assert event.title == "Summer Concert"
      assert event.description == "A great concert"
      assert event.url == "https://example.com/concert"
      assert event.date == "Aug 15"
      assert event.position == 1
      assert event.xpath == "/html/body/div"
    end

    test "creates event with event_dates" do
      attrs = %{
        title: "Concert",
        event_dates: %{
          start_datetime: "2024-08-15T19:00:00",
          end_datetime: "2024-08-15T22:00:00",
          displayed_dates: "Aug 15"
        }
      }

      event = GoogleEvent.new(attrs)

      assert event.event_dates.start_datetime == "2024-08-15T19:00:00"
      assert event.event_dates.end_datetime == "2024-08-15T22:00:00"
      assert event.event_dates.displayed_dates == "Aug 15"
    end

    test "creates event with location" do
      attrs = %{
        title: "Concert",
        location: %{
          name: "Madison Square Garden",
          address: "4 Pennsylvania Plaza, New York, NY 10001",
          url: "https://www.msg.com",
          cid: "12345",
          feature_id: "0x89c25"
        }
      }

      event = GoogleEvent.new(attrs)

      assert event.location.name == "Madison Square Garden"
      assert event.location.address == "4 Pennsylvania Plaza, New York, NY 10001"
      assert event.location.url == "https://www.msg.com"
      assert event.location.cid == "12345"
      assert event.location.feature_id == "0x89c25"
    end

    test "creates event with ticket information" do
      attrs = %{
        title: "Concert",
        tickets_url: "https://tickets.example.com",
        more_info_url: "https://info.example.com",
        information_and_tickets: [
          %{
            type: "tickets",
            title: "Ticketmaster",
            description: "Buy tickets",
            url: "https://www.ticketmaster.com/event/123",
            domain: "www.ticketmaster.com"
          }
        ]
      }

      event = GoogleEvent.new(attrs)

      assert event.tickets_url == "https://tickets.example.com"
      assert event.more_info_url == "https://info.example.com"
      assert length(event.information_and_tickets) == 1
      assert List.first(event.information_and_tickets).domain == "www.ticketmaster.com"
    end

    test "creates event with image_url" do
      attrs = %{
        title: "Concert",
        image_url: "https://example.com/image.jpg"
      }

      event = GoogleEvent.new(attrs)

      assert event.image_url == "https://example.com/image.jpg"
    end

    test "creates event with nil fields for missing attributes" do
      attrs = %{title: "Concert"}

      event = GoogleEvent.new(attrs)

      assert event.title == "Concert"
      assert is_nil(event.description)
      assert is_nil(event.url)
      assert is_nil(event.date)
      assert is_nil(event.event_dates)
      assert is_nil(event.location)
    end

    test "creates event from empty map" do
      event = GoogleEvent.new(%{})

      assert %GoogleEvent{} = event
      assert is_nil(event.title)
      assert is_nil(event.description)
    end
  end
end
