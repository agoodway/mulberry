#!/usr/bin/env elixir

# Example script showing improved event extraction
# Run with: elixir examples/extract_events.exs

Mix.install([
  {:mulberry, path: "."},
  {:jason, "~> 1.4"}
])

defmodule EventExtractor do
  alias Mulberry.Extractors.EventsExtractor
  
  def run do
    IO.puts("🔍 Extracting events from events.md...\n")
    
    # Read the markdown file
    {:ok, content} = File.read("events.md")
    
    # Extract with full details
    IO.puts("Extracting with comprehensive details...")
    {:ok, events} = EventsExtractor.extract(content, include_descriptions: true)
    
    # Validate the events
    IO.puts("Validating extracted events...")
    {:ok, validated_events} = EventsExtractor.validate_events(events)
    
    # Enhance with computed fields
    IO.puts("Enhancing events with computed fields...")
    enhanced_events = EventsExtractor.enhance_events(validated_events)
    
    # Write to file
    output_path = "events-enhanced.json"
    json = Jason.encode!(enhanced_events, pretty: true)
    File.write!(output_path, json)
    
    IO.puts("\n✅ Successfully extracted #{length(enhanced_events)} events to #{output_path}")
    
    # Print summary
    print_summary(enhanced_events)
    
    # Show sample of first event
    IO.puts("\n📋 Sample of first extracted event:")
    first_event = List.first(enhanced_events)
    IO.puts("  Title: #{first_event["title"]}")
    IO.puts("  Date: #{get_in(first_event, ["date", "startDate"])}")
    IO.puts("  Time: #{get_in(first_event, ["time", "startTime"])} - #{get_in(first_event, ["time", "endTime"])}")
    
    if first_event["description"] do
      IO.puts("  Description: #{String.slice(first_event["description"], 0, 100)}...")
    end
    
    if get_in(first_event, ["registration", "required"]) do
      seats = get_in(first_event, ["registration", "seatsAvailable"])
      IO.puts("  Registration: Required (#{seats} seats available)")
    end
    
    if get_in(first_event, ["date", "isRecurring"]) do
      IO.puts("  ⚡ This is a recurring event")
    end
  end
  
  defp print_summary(events) do
    IO.puts("\n📊 Extraction Summary:")
    IO.puts("  Total events: #{length(events)}")
    
    # Count events with descriptions
    with_descriptions = Enum.count(events, &Map.has_key?(&1, "description"))
    IO.puts("  Events with descriptions: #{with_descriptions}")
    
    # Count events with registration
    with_registration = Enum.count(events, &(get_in(&1, ["registration", "required"]) == true))
    IO.puts("  Events requiring registration: #{with_registration}")
    
    # Count recurring events
    recurring = Enum.count(events, &(get_in(&1, ["date", "isRecurring"]) == true))
    IO.puts("  Recurring events: #{recurring}")
    
    # Show audience breakdown
    audiences = 
      events
      |> Enum.flat_map(&(Map.get(&1, "audience", [])))
      |> Enum.frequencies()
    
    IO.puts("\n  Audience breakdown:")
    Enum.each(audiences, fn {audience, count} ->
      IO.puts("    • #{audience}: #{count} events")
    end)
  end
end

# Run the extractor
EventExtractor.run()