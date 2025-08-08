#!/usr/bin/env elixir

# Example: Extract events from a conference schedule
# Run with: elixir examples/extract_conference_events.exs

Mix.install([
  {:mulberry, path: "."},
  {:jason, "~> 1.4"}
])

defmodule ConferenceExtractor do
  alias Mulberry.Extractors.EventsExtractor
  
  def run do
    # Sample conference schedule content
    content = """
    # Tech Summit 2025 - Schedule

    ## Day 1: August 15, 2025

    ### Opening Keynote
    **Time:** 9:00 AM - 10:00 AM
    **Location:** Main Auditorium
    **Speaker:** Jane Smith, CEO of TechCorp
    **Description:** Join us for an inspiring opening keynote about the future of technology and innovation.
    **Registration:** Required - Limited to 500 attendees
    
    ### Workshop: Machine Learning Basics
    **Time:** 10:30 AM - 12:30 PM  
    **Location:** Workshop Room A
    **Audience:** Beginners, Students
    **Categories:** AI/ML, Hands-on
    **Description:** A hands-on workshop introducing the fundamentals of machine learning with practical examples.
    **Registration:** Required - 30 seats available
    **URL:** https://techsummit.com/workshops/ml-basics
    
    ### Networking Lunch
    **Time:** 12:30 PM - 2:00 PM
    **Location:** Conference Hall Lobby
    **Type:** In-Person
    **Categories:** Networking, Social
    
    ## Day 2: August 16, 2025
    
    ### Panel Discussion: Future of Web3
    **Time:** 2:00 PM - 3:30 PM
    **Location:** Panel Room B
    **Type:** Hybrid (In-Person + Virtual)
    **Panelists:** Industry experts from leading blockchain companies
    **Categories:** Blockchain, Web3, Panel
    **Stream URL:** https://techsummit.com/live/web3-panel
    
    ### Closing Reception
    **Time:** 6:00 PM - 8:00 PM
    **Location:** Rooftop Terrace
    **Type:** In-Person
    **Categories:** Networking, Social
    **Notes:** Cocktails and appetizers will be served
    """
    
    IO.puts("🎯 Extracting conference events...\n")
    
    case EventsExtractor.extract(content, include_descriptions: true) do
      {:ok, events} ->
        IO.puts("✅ Successfully extracted #{length(events)} events\n")
        
        # Display extracted events
        Enum.each(events, fn event ->
          IO.puts("📅 #{event["title"]}")
          IO.puts("   Date: #{get_in(event, ["date", "startDate"])}")
          IO.puts("   Time: #{get_in(event, ["time", "startTime"])} - #{get_in(event, ["time", "endTime"])}")
          IO.puts("   Location: #{get_in(event, ["location", "venueName"])}")
          
          if event["eventType"] do
            IO.puts("   Type: #{event["eventType"]}")
          end
          
          if event["categories"] && length(event["categories"]) > 0 do
            IO.puts("   Categories: #{Enum.join(event["categories"], ", ")}")
          end
          
          if get_in(event, ["registration", "required"]) do
            seats = get_in(event, ["registration", "seatsAvailable"])
            if seats do
              IO.puts("   ⚠️  Registration required (#{seats} seats available)")
            else
              IO.puts("   ⚠️  Registration required")
            end
          end
          
          IO.puts("")
        end)
        
        # Save to JSON file
        output_file = "conference-events.json"
        json = Jason.encode!(events, pretty: true)
        File.write!(output_file, json)
        IO.puts("💾 Events saved to #{output_file}")
        
      {:error, reason} ->
        IO.puts("❌ Failed to extract events: #{inspect(reason)}")
    end
  end
end

# Run the extractor
ConferenceExtractor.run()