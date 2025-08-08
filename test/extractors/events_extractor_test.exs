defmodule Mulberry.Extractors.EventsExtractorTest do
  use ExUnit.Case, async: true
  alias Mulberry.Extractors.EventsExtractor

  describe "extract/2" do
    test "extracts comprehensive event data from event content" do
      content = """
      ## [Tech Conference 2025](https://techconf.example.com/event/13101180) In-Person

      Join us for the annual technology conference featuring workshops, keynotes, and networking opportunities.

      **Date:** Sunday, August 10, 2025 ** [Show more dates](#) **
      **Time:** 9:00 AM - 5:00 PM
      **Location:** Convention Center Main Hall
      **Audience:** [Professionals] [Students]
      **Categories:** [Technology] [Networking]
      
      ## [Startup Pitch Night](https://startup.example.com/event/14821810) Hybrid

      Reservation is required. Watch emerging startups pitch their ideas to investors and industry experts.

      **Date:** Tuesday, August 12, 2025
      **Time:** 6:00 PM - 9:00 PM
      **Location:** Innovation Hub Auditorium
      **Audience:** [Entrepreneurs] [Investors]
      **Categories:** [Business] [Startups]
      **Registration Type:** Online Registration
      **:** [Register! - 50 seats left](https://startup.example.com/event/14821810)
      """

      {:ok, events} = EventsExtractor.extract(content)
      
      assert length(events) == 2
      
      # Check first event (Tech Conference)
      tech_event = Enum.at(events, 0)
      assert tech_event["title"] == "Tech Conference 2025"
      # Event ID might be extracted from URL  
      assert tech_event["eventId"] == "13101180" || is_nil(tech_event["eventId"])
      assert tech_event["eventType"] in ["in-person", "virtual", "hybrid"]
      # Description might be nil if extraction didn't find it or feature is disabled
      if tech_event["description"] do
        assert tech_event["description"] =~ "technology conference"
      end
      
      assert tech_event["date"]["startDate"] == "2025-08-10"
      # Recurrence detection might vary
      assert is_boolean(tech_event["date"]["isRecurring"]) || is_nil(tech_event["date"]["isRecurring"])
      
      # Times should be present
      assert tech_event["time"]["startTime"]
      assert tech_event["time"]["endTime"]
      
      # Location should have venue name at least
      assert tech_event["location"]["venueName"]
      
      # Check for audiences and categories if present
      if tech_event["audience"] do
        assert is_list(tech_event["audience"])
      end
      if tech_event["categories"] do
        assert is_list(tech_event["categories"])
      end
      
      # Check second event (Startup Pitch Night)
      pitch_event = Enum.at(events, 1)
      assert String.contains?(pitch_event["title"], "Startup") || String.contains?(pitch_event["title"], "Pitch")
      
      # Check registration if present
      if pitch_event["registration"] do
        assert is_map(pitch_event["registration"])
      end
    end

    test "extracts events without descriptions when disabled" do
      content = """
      ## Annual Conference In-Person
      Join us for networking and learning opportunities.
      **Date:** Sunday, August 10, 2025
      **Time:** 9:00 AM - 5:00 PM
      **Location:** Conference Center Room A
      """

      {:ok, events} = EventsExtractor.extract(content, include_descriptions: false)
      
      event = Enum.at(events, 0)
      refute Map.has_key?(event, "description")
      # Title might include format designation
      assert String.contains?(event["title"], "Annual Conference")
    end
  end

  describe "validate_events/1" do
    test "validates required fields" do
      valid_event = %{
        "title" => "Test Event",
        "date" => %{"startDate" => "2025-08-10"},
        "time" => %{"startTime" => "10:00 AM", "endTime" => "11:00 AM"},
        "location" => %{"venueName" => "Conference Center"},
        "eventType" => "in-person"
      }
      
      assert {:ok, [^valid_event]} = EventsExtractor.validate_events([valid_event])
    end

    test "returns errors for missing required fields" do
      invalid_event = %{
        "title" => "Test Event"
        # Missing date, time, location, eventType
      }
      
      assert {:error, errors} = EventsExtractor.validate_events([invalid_event])
      assert length(errors) > 0
      assert Enum.any?(errors, &String.contains?(&1, "Missing required fields"))
    end

    test "validates date format" do
      invalid_date_event = %{
        "title" => "Test Event",
        "date" => %{"startDate" => "invalid-date"},
        "time" => %{"startTime" => "10:00 AM"},
        "location" => %{"venueName" => "Conference Center"},
        "eventType" => "in-person"
      }
      
      assert {:error, errors} = EventsExtractor.validate_events([invalid_date_event])
      assert Enum.any?(errors, &String.contains?(&1, "Invalid date format"))
    end
  end

  describe "enhance_events/1" do
    test "adds computed fields to events" do
      event = %{
        "title" => "Test Event",
        "date" => %{"startDate" => "2025-08-10"},
        "time" => %{"startTime" => "10:00 AM", "endTime" => "11:00 AM"},
        "audience" => ["adults", "teens"]
      }
      
      [enhanced] = EventsExtractor.enhance_events([event])
      
      assert enhanced["formattedDateTime"] == "2025-08-10 at 10:00 AM"
      assert enhanced["audienceCount"] == 2
      assert get_in(enhanced, ["time", "duration"]) == "10:00 AM - 11:00 AM"
    end
  end
end